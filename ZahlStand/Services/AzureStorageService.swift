import Foundation
import CryptoKit

// MARK: - Legacy Format Structures

struct LegacySonglist {
    let name: String
    let id: Int
    let songs: [LegacySong]
}

struct LegacySong {
    let name: String
    let path: String
    let fileData: Data?
    let midiCommands: String?
}

// MARK: - Azure Storage Service

@MainActor
class AzureStorageService: ObservableObject {
    @Published var isUploading = false
    @Published var isDownloading = false
    @Published var uploadProgress = 0.0
    @Published var downloadProgress = 0.0
    @Published var availableBlobs: [String] = []
    @Published var legacyBlobs: [String] = []
    
    private let accountName: String
    private let accountKey: String
    private let legacyContainer: String
    private let newContainer: String
    
    private var keyData: Data? { Data(base64Encoded: accountKey) }
    private var baseURL: String { "https://\(accountName).blob.core.windows.net" }
    
    init(accountName: String, accountKey: String, containerName: String = "playlists") {
        self.accountName = accountName
        self.accountKey = accountKey
        self.legacyContainer = AppConfig.azureLegacyContainer
        self.newContainer = AppConfig.azureNewContainer
    }
    
    // MARK: - Auth
    
    private func authorize(method: String, contentLength: Int = 0, contentType: String = "",
                          date: String, headers: String, resource: String) -> String? {
        guard let keyData = keyData else { return nil }
        let toSign = [method,"","",contentLength > 0 ? "\(contentLength)" : "","",contentType,
                      "","","","","","",headers,resource].joined(separator: "\n")
        let key = SymmetricKey(data: keyData)
        let sig = HMAC<SHA256>.authenticationCode(for: Data(toSign.utf8), using: key)
        return "SharedKey \(accountName):\(Data(sig).base64EncodedString())"
    }
    
    private func xmsDate() -> String {
        let f = DateFormatter()
        f.dateFormat = "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "GMT")
        return f.string(from: Date())
    }
    
    // MARK: - Container
    
    func createContainerIfNeeded() async throws {
        let date = xmsDate()
        let headers = "x-ms-date:\(date)\nx-ms-version:2021-06-08"
        let resource = "/\(accountName)/\(newContainer)\nrestype:container"
        guard let auth = authorize(method: "PUT", date: date, headers: headers, resource: resource)
        else { throw AzureError.authFailed }
        
        var req = URLRequest(url: URL(string: "\(baseURL)/\(newContainer)?restype=container")!)
        req.httpMethod = "PUT"
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.setValue(date, forHTTPHeaderField: "x-ms-date")
        req.setValue("2021-06-08", forHTTPHeaderField: "x-ms-version")
        req.setValue(auth, forHTTPHeaderField: "Authorization")
        
        let (_, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 201 && http.statusCode != 409 {
            throw AzureError.containerFailed(http.statusCode)
        }
    }
    
    // MARK: - List
    
    func listLegacyBlobs() async throws { legacyBlobs = try await listBlobs(in: legacyContainer) }
    func listNewBlobs() async throws { availableBlobs = try await listBlobs(in: newContainer) }
    
    private func listBlobs(in container: String) async throws -> [String] {
        let date = xmsDate()
        let headers = "x-ms-date:\(date)\nx-ms-version:2021-06-08"
        let resource = "/\(accountName)/\(container)\ncomp:list\nrestype:container"
        guard let auth = authorize(method: "GET", date: date, headers: headers, resource: resource)
        else { throw AzureError.authFailed }
        
        var req = URLRequest(url: URL(string: "\(baseURL)/\(container)?restype=container&comp=list")!)
        req.httpMethod = "GET"
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.setValue(date, forHTTPHeaderField: "x-ms-date")
        req.setValue("2021-06-08", forHTTPHeaderField: "x-ms-version")
        req.setValue(auth, forHTTPHeaderField: "Authorization")
        
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 200 {
            throw AzureError.listFailed(http.statusCode)
        }
        return BlobListParser(data: data).parse()
    }
    
    // MARK: - Download
    
    func downloadLegacyBlob(name: String) async throws -> Data {
        try await downloadBlob(name: name, from: legacyContainer)
    }
    
    func downloadNewBlob(name: String) async throws -> Data {
        try await downloadBlob(name: name, from: newContainer)
    }
    
    private func downloadBlob(name: String, from container: String) async throws -> Data {
        isDownloading = true
        downloadProgress = 0
        defer { isDownloading = false }

        // Try with encoded name in signature first (matching how it was uploaded)
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name

        let date = xmsDate()
        let headers = "x-ms-date:\(date)\nx-ms-version:2021-06-08"

        // Use ENCODED name in resource (to match upload behavior)
        let resource = "/\(accountName)/\(container)/\(encodedName)"
        guard let auth = authorize(method: "GET", date: date, headers: headers, resource: resource)
        else { throw AzureError.authFailed }

        let urlString = "\(baseURL)/\(container)/\(encodedName)"
        var req = URLRequest(url: URL(string: urlString)!)
        req.httpMethod = "GET"
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.setValue(date, forHTTPHeaderField: "x-ms-date")
        req.setValue("2021-06-08", forHTTPHeaderField: "x-ms-version")
        req.setValue(auth, forHTTPHeaderField: "Authorization")

        print("📥 Downloading: \(name)")

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse {
            print("📥 Response: \(http.statusCode)")
            if http.statusCode != 200 {
                if let errorBody = String(data: data, encoding: .utf8) {
                    print("📥 Error: \(errorBody)")
                }
                throw AzureError.downloadFailed(http.statusCode)
            }
        }
        downloadProgress = 1
        return data
    }
    
    // MARK: - Upload
    
    func uploadSonglist(_ songlist: Songlist, documentService: DocumentService, annotationService: AnnotationService? = nil) async throws {
        isUploading = true
        uploadProgress = 0
        defer { isUploading = false }

        let data = try exportSonglist(songlist, documentService: documentService, annotationService: annotationService)

        // Sanitize blob name
        let sanitizedName = songlist.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "#", with: "")
        let blobName = "\(sanitizedName).json"

        // URL encode the blob name for the URL
        let encodedBlobName = blobName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? blobName

        print("📤 Uploading: \(blobName) (\(data.count) bytes)")

        let date = xmsDate()
        let headers = "x-ms-blob-type:BlockBlob\nx-ms-date:\(date)\nx-ms-version:2021-06-08"
        // Use encoded blob name in the resource for signature
        let resource = "/\(accountName)/\(newContainer)/\(encodedBlobName)"

        guard let auth = authorize(method: "PUT", contentLength: data.count, contentType: "application/json",
                                   date: date, headers: headers, resource: resource)
        else { throw AzureError.authFailed }

        let urlString = "\(baseURL)/\(newContainer)/\(encodedBlobName)"
        
        var req = URLRequest(url: URL(string: urlString)!)
        req.httpMethod = "PUT"
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.httpBody = data
        req.setValue(date, forHTTPHeaderField: "x-ms-date")
        req.setValue("2021-06-08", forHTTPHeaderField: "x-ms-version")
        req.setValue(auth, forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
        req.setValue("BlockBlob", forHTTPHeaderField: "x-ms-blob-type")
        
        let (responseData, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse {
            print("📤 Response: \(http.statusCode)")
            if http.statusCode != 201 {
                if let errorStr = String(data: responseData, encoding: .utf8) {
                    print("📤 Error body: \(errorStr)")
                }
                throw AzureError.uploadFailed(http.statusCode)
            }
        }
        uploadProgress = 1
    }
    
    private func exportSonglist(_ songlist: Songlist, documentService: DocumentService, annotationService: AnnotationService? = nil) throws -> Data {
        var songs: [[String: Any]] = []
        for song in songlist.songs {
            var s: [String: Any] = ["id": song.id, "title": song.title,
                                    "fileName": song.fileName, "fileExtension": song.fileExtension]
            if let v = song.artist { s["artist"] = v }
            if let v = song.key { s["key"] = v }
            if let v = song.tempo { s["tempo"] = v }
            if let v = song.notes { s["notes"] = v }
            if let v = song.pageCount { s["pageCount"] = v }

            // Export MIDI profiles (new format)
            if song.hasAnyMIDIProfile {
                let profilesData = song.midiProfiles.compactMap { profile -> [String: Any]? in
                    guard profile.hasProgramChange else { return nil }
                    var p: [String: Any] = [
                        "id": profile.id,
                        "instrumentType": profile.instrumentType.rawValue
                    ]
                    if let v = profile.channel { p["channel"] = v }
                    if let v = profile.programNumber { p["programNumber"] = v }
                    if let v = profile.bankMSB { p["bankMSB"] = v }
                    if let v = profile.bankLSB { p["bankLSB"] = v }
                    if let v = profile.label { p["label"] = v }
                    return p
                }
                if !profilesData.isEmpty {
                    s["midiProfiles"] = profilesData
                }
            }

            // Also export legacy fields for backward compatibility
            if song.hasMIDIProgramChange {
                let legacyProfile = song.midiProfile(for: .keyboard) ?? song.primaryMIDIProfile
                if let v = legacyProfile?.channel ?? song.midiChannel { s["midiChannel"] = v }
                if let v = legacyProfile?.programNumber ?? song.midiProgramNumber { s["midiProgramNumber"] = v }
                if let v = legacyProfile?.bankMSB ?? song.midiBankMSB { s["midiBankMSB"] = v }
                if let v = legacyProfile?.bankLSB ?? song.midiBankLSB { s["midiBankLSB"] = v }
            }

            // Export annotation profiles (version 4+)
            if let annotationService = annotationService {
                // Temporarily load annotations for this song
                annotationService.loadAnnotations(for: song.fullFileName)
                let annotationProfiles = annotationService.exportProfiles()
                if !annotationProfiles.isEmpty {
                    let profilesData = annotationProfiles.map { profile -> [String: Any] in
                        var p: [String: Any] = [
                            "id": profile.id,
                            "name": profile.name,
                            "isDefault": profile.isDefault
                        ]
                        if let ownerName = profile.ownerName {
                            p["ownerName"] = ownerName
                        }
                        if !profile.annotations.isEmpty {
                            p["annotations"] = profile.annotations.map { ann -> [String: Any] in
                                [
                                    "id": ann.id,
                                    "pageIndex": ann.pageIndex,
                                    "relativeX": ann.relativeX,
                                    "relativeY": ann.relativeY,
                                    "text": ann.text,
                                    "color": ann.color.rawValue,
                                    "fontSize": ann.fontSize.rawValue,
                                    "isBold": ann.isBold
                                ]
                            }
                        }
                        return p
                    }
                    s["annotationProfiles"] = profilesData
                }
            }

            if let path = song.filePath, let data = try? Data(contentsOf: path) {
                s["fileData"] = data.base64EncodedString()
            }
            songs.append(s)
        }
        let dict: [String: Any] = ["version": 4, "name": songlist.name, "id": songlist.id,
                                   "event": songlist.event as Any, "venue": songlist.venue as Any,
                                   "dateCreated": ISO8601DateFormatter().string(from: songlist.dateCreated),
                                   "dateModified": ISO8601DateFormatter().string(from: songlist.dateModified),
                                   "songs": songs]
        return try JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted)
    }
    
    // MARK: - Delete
    
    func deleteSonglist(name: String) async throws {
        let encodedName = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name

        let date = xmsDate()
        let headers = "x-ms-date:\(date)\nx-ms-version:2021-06-08"
        // Use encoded name in resource for signature
        let resource = "/\(accountName)/\(newContainer)/\(encodedName)"
        guard let auth = authorize(method: "DELETE", date: date, headers: headers, resource: resource)
        else { throw AzureError.authFailed }

        var req = URLRequest(url: URL(string: "\(baseURL)/\(newContainer)/\(encodedName)")!)
        req.httpMethod = "DELETE"
        req.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        req.setValue(date, forHTTPHeaderField: "x-ms-date")
        req.setValue("2021-06-08", forHTTPHeaderField: "x-ms-version")
        req.setValue(auth, forHTTPHeaderField: "Authorization")

        let (_, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode != 202 {
            throw AzureError.deleteFailed(http.statusCode)
        }
    }
    
    // MARK: - Parse Legacy
    
    func parseLegacyBlob(_ data: Data) throws -> LegacySonglist {
        let plistData: Data
        if data.count > 2 && data[0] == 0x1f && data[1] == 0x8b {
            print("📦 Gzip: \(data.count) bytes")
            plistData = try GzipHelper.decompress(data)
            print("✅ Decompressed: \(plistData.count) bytes")
        } else {
            plistData = data
        }
        
        guard let outer = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
              let objs = outer["$objects"] as? [Any], objs.count > 3,
              let innerDict = objs[3] as? [String: Any],
              let inner = innerDict["NS.data"] as? Data
        else { throw AzureError.invalidFormat("Outer plist") }
        
        guard let innerPlist = try? PropertyListSerialization.propertyList(from: inner, format: nil) as? [String: Any],
              let innerObjs = innerPlist["$objects"] as? [Any], innerObjs.count > 1,
              let slObj = innerObjs[1] as? [String: Any]
        else { throw AzureError.invalidFormat("Inner plist") }
        
        let name = resolveUID(slObj["songlistName"], in: innerObjs) as? String ?? "Unknown"
        let id = slObj["songlistID"] as? Int ?? 0
        print("📋 \(name) (ID: \(id))")
        
        var songs: [LegacySong] = []
        if let songsObj = resolveUID(slObj["songs"], in: innerObjs) as? [String: Any],
           let refs = songsObj["NS.objects"] as? [Any] {
            print("🎵 \(refs.count) songs")
            for ref in refs {
                if let s = resolveUID(ref, in: innerObjs) as? [String: Any] {
                    let songName = resolveUID(s["songName"], in: innerObjs) as? String ?? ""
                    let songPath = resolveUID(s["songPath"], in: innerObjs) as? String ?? ""
                    let fileData = resolveUID(s["actualFile"], in: innerObjs) as? Data
                    let midiCmds = resolveUID(s["midiCommands"], in: innerObjs) as? String
                    
                    songs.append(LegacySong(name: songName, path: songPath, fileData: fileData, midiCommands: midiCmds))
                }
            }
        }
        return LegacySonglist(name: name, id: id, songs: songs)
    }
    
    private func resolveUID(_ value: Any?, in objects: [Any]) -> Any? {
        guard let value = value else { return nil }
        
        if let dict = value as? [String: Any], let uid = dict["CF$UID"] as? Int {
            guard uid >= 0 && uid < objects.count else { return nil }
            let resolved = objects[uid]
            if let str = resolved as? String, str == "$null" { return nil }
            return resolved
        }
        
        let description = String(describing: value)
        if description.contains("CFKeyedArchiverUID") {
            if let range = description.range(of: "value = "),
               let endRange = description.range(of: "}", range: range.upperBound..<description.endIndex) {
                let valueStr = description[range.upperBound..<endRange.lowerBound]
                if let uid = Int(valueStr.trimmingCharacters(in: .whitespaces)) {
                    guard uid >= 0 && uid < objects.count else { return nil }
                    let resolved = objects[uid]
                    if let str = resolved as? String, str == "$null" { return nil }
                    return resolved
                }
            }
        }
        
        return value
    }
    
    private func parseLegacyMIDI(_ midiString: String?) -> (channel: Int, program: Int, bankMSB: Int, bankLSB: Int)? {
        guard let midi = midiString, !midi.isEmpty else { return nil }
        
        let trimmed = midi.trimmingCharacters(in: .whitespaces)
        
        if trimmed.contains("-") {
            let parts = trimmed.components(separatedBy: "-")
            guard parts.count == 2, let channel = Int(parts[0]), let program = Int(parts[1]) else { return nil }
            return (channel: channel, program: program, bankMSB: 0, bankLSB: 3)
        } else {
            guard let program = Int(trimmed) else { return nil }
            return (channel: 0, program: program, bankMSB: 0, bankLSB: 3)
        }
    }
    
    func convertAndImportLegacy(_ legacy: LegacySonglist, documentService: DocumentService,
                                songlistService: SonglistService) async throws -> Songlist {
        var ids: [String] = []
        for s in legacy.songs {
            var song: Song?

            // Try exact match first, then fallback to PDF for migrated Word files
            let ext = (s.path as NSString).pathExtension.lowercased()
            let baseName = (s.path as NSString).deletingPathExtension

            let existing: Song? = documentService.songs.first(where: { $0.fullFileName == s.path })
                ?? (["doc", "docx"].contains(ext)
                    ? documentService.songs.first(where: { $0.fileName == baseName && $0.isPDF })
                    : nil)

            if let existing = existing {
                song = existing
                ids.append(existing.id)
            } else if let data = s.fileData, !data.isEmpty {
                song = try await documentService.importEmbeddedFile(name: s.name, fileName: s.path, data: data)
                ids.append(song!.id)
            }
            
            if let song = song, let midi = parseLegacyMIDI(s.midiCommands) {
                song.midiChannel = midi.channel
                song.midiProgramNumber = midi.program
                song.midiBankMSB = midi.bankMSB
                song.midiBankLSB = midi.bankLSB
                documentService.saveSong(song)
                print("🎹 MIDI: \(s.name) → Ch:\(midi.channel) Pg:\(midi.program)")
            }
        }
        let sl = Songlist(name: legacy.name, songIds: ids)
        sl.documentService = documentService
        try songlistService.saveSonglist(sl)

        // Refresh songs list to reflect any new imports or MIDI updates
        documentService.loadSongs()

        return sl
    }
    
    func downloadAndImportSonglist(name: String, documentService: DocumentService,
                                   songlistService: SonglistService,
                                   annotationService: AnnotationService? = nil) async throws -> Songlist {
        let data = try await downloadNewBlob(name: name)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AzureError.invalidFormat("JSON")
        }
        let slName = json["name"] as? String ?? "Unknown"
        var ids: [String] = []
        if let songs = json["songs"] as? [[String: Any]] {
            for s in songs {
                let baseName = s["fileName"] as? String ?? ""
                let ext = s["fileExtension"] as? String ?? ""
                let fn = "\(baseName).\(ext)"

                // Try exact match first, then fallback to PDF for migrated Word files
                let existing: Song? = documentService.songs.first(where: { $0.fullFileName == fn })
                    ?? (["doc", "docx"].contains(ext.lowercased())
                        ? documentService.songs.first(where: { $0.fileName == baseName && $0.isPDF })
                        : nil)

                if let existing = existing {
                    // Song exists - apply MIDI settings from cloud if present
                    applyMIDISettings(from: s, to: existing)
                    // Apply annotation profiles if present
                    if let annotationService = annotationService {
                        applyAnnotationSettings(from: s, to: existing, annotationService: annotationService)
                    }
                    documentService.saveSong(existing)
                    ids.append(existing.id)
                } else if let b64 = s["fileData"] as? String, let fileData = Data(base64Encoded: b64) {
                    // New song - import file and apply MIDI settings
                    let song = try await documentService.importEmbeddedFile(name: s["title"] as? String ?? "", fileName: fn, data: fileData)
                    applyMIDISettings(from: s, to: song)
                    // Apply annotation profiles if present
                    if let annotationService = annotationService {
                        applyAnnotationSettings(from: s, to: song, annotationService: annotationService)
                    }
                    documentService.saveSong(song)
                    ids.append(song.id)
                }
            }
        }
        let sl = Songlist(name: slName, songIds: ids)
        sl.event = json["event"] as? String
        sl.venue = json["venue"] as? String
        sl.documentService = documentService
        try songlistService.saveSonglist(sl)

        // Refresh songs list to reflect any new imports or MIDI updates
        documentService.loadSongs()

        return sl
    }

    /// Apply MIDI settings from cloud data to a song (retains cloud settings when present)
    private func applyMIDISettings(from cloudData: [String: Any], to song: Song) {
        // Try to parse new format profiles first
        if let profilesData = cloudData["midiProfiles"] as? [[String: Any]], !profilesData.isEmpty {
            var profiles: [MIDIProfile] = []
            for profileDict in profilesData {
                guard let typeRaw = profileDict["instrumentType"] as? String,
                      let type = MIDIInstrumentType(rawValue: typeRaw) else { continue }

                let profile = MIDIProfile(
                    id: profileDict["id"] as? String ?? UUID().uuidString,
                    instrumentType: type,
                    channel: profileDict["channel"] as? Int,
                    programNumber: profileDict["programNumber"] as? Int,
                    bankMSB: profileDict["bankMSB"] as? Int,
                    bankLSB: profileDict["bankLSB"] as? Int,
                    label: profileDict["label"] as? String
                )
                if profile.hasProgramChange {
                    profiles.append(profile)
                }
            }
            if !profiles.isEmpty {
                song.midiProfiles = profiles
                // Also update legacy fields from keyboard profile
                if let keyboardProfile = profiles.first(where: { $0.instrumentType == .keyboard }) {
                    song.midiChannel = keyboardProfile.channel
                    song.midiProgramNumber = keyboardProfile.programNumber
                    song.midiBankMSB = keyboardProfile.bankMSB
                    song.midiBankLSB = keyboardProfile.bankLSB
                }
                return
            }
        }

        // Fall back to legacy fields
        if let channel = cloudData["midiChannel"] as? Int {
            song.midiChannel = channel
        }
        if let program = cloudData["midiProgramNumber"] as? Int {
            song.midiProgramNumber = program
        }
        if let bankMSB = cloudData["midiBankMSB"] as? Int {
            song.midiBankMSB = bankMSB
        }
        if let bankLSB = cloudData["midiBankLSB"] as? Int {
            song.midiBankLSB = bankLSB
        }

        // Migrate legacy to profile if no profiles exist
        if song.midiProfiles.isEmpty, let program = song.midiProgramNumber {
            let profile = MIDIProfile(
                instrumentType: .keyboard,
                channel: song.midiChannel,
                programNumber: program,
                bankMSB: song.midiBankMSB,
                bankLSB: song.midiBankLSB
            )
            song.midiProfiles = [profile]
        }
    }

    /// Apply annotation settings from cloud data to a song
    private func applyAnnotationSettings(from cloudData: [String: Any], to song: Song, annotationService: AnnotationService) {
        guard let profilesData = cloudData["annotationProfiles"] as? [[String: Any]], !profilesData.isEmpty else {
            return
        }

        // Parse annotation profiles from cloud data
        var profiles: [AnnotationProfile] = []
        for profileDict in profilesData {
            let profileId = profileDict["id"] as? String ?? UUID().uuidString
            let name = profileDict["name"] as? String ?? "Imported"
            let ownerName = profileDict["ownerName"] as? String
            let isDefault = profileDict["isDefault"] as? Bool ?? false

            var annotations: [PDFAnnotation] = []
            if let annotationsData = profileDict["annotations"] as? [[String: Any]] {
                for annDict in annotationsData {
                    let annotation = PDFAnnotation(
                        id: annDict["id"] as? String ?? UUID().uuidString,
                        pageIndex: annDict["pageIndex"] as? Int ?? 0,
                        relativeX: annDict["relativeX"] as? CGFloat ?? 0.5,
                        relativeY: annDict["relativeY"] as? CGFloat ?? 0.5,
                        text: annDict["text"] as? String ?? "",
                        color: AnnotationColor(rawValue: annDict["color"] as? String ?? "yellow") ?? .yellow,
                        fontSize: AnnotationFontSize(rawValue: annDict["fontSize"] as? String ?? "small") ?? .small,
                        isBold: annDict["isBold"] as? Bool ?? false
                    )
                    annotations.append(annotation)
                }
            }

            let profile = AnnotationProfile(
                id: profileId,
                name: name,
                ownerName: ownerName,
                isDefault: isDefault,
                annotations: annotations
            )
            profiles.append(profile)
        }

        // Import the profiles into the annotation service
        if !profiles.isEmpty {
            annotationService.loadAnnotations(for: song.fullFileName)
            annotationService.importProfiles(profiles, merge: true)
            print("📝 Annotations: \(song.title) → \(profiles.count) profiles imported")
        }
    }
}

// MARK: - Parser

class BlobListParser: NSObject, XMLParserDelegate {
    private let data: Data
    private var blobs: [String] = []
    private var el = "", name = ""
    
    init(data: Data) { self.data = data }
    func parse() -> [String] { let p = XMLParser(data: data); p.delegate = self; p.parse(); return blobs }
    func parser(_ p: XMLParser, didStartElement e: String, namespaceURI: String?, qualifiedName: String?, attributes: [String:String]=[:]) {
        el = e; if e == "Blob" { name = "" }
    }
    func parser(_ p: XMLParser, foundCharacters s: String) { if el == "Name" { name += s } }
    func parser(_ p: XMLParser, didEndElement e: String, namespaceURI: String?, qualifiedName: String?) {
        if e == "Blob" && !name.isEmpty { blobs.append(name.trimmingCharacters(in: .whitespacesAndNewlines)) }; el = ""
    }
}

// MARK: - Errors

enum AzureError: LocalizedError {
    case authFailed, containerFailed(Int), listFailed(Int), downloadFailed(Int), uploadFailed(Int), deleteFailed(Int), invalidFormat(String), decompressionFailed
    var errorDescription: String? {
        switch self {
        case .authFailed: return "Auth failed"
        case .containerFailed(let c): return "Container (\(c))"
        case .listFailed(let c): return "List (\(c))"
        case .downloadFailed(let c): return "Download (\(c))"
        case .uploadFailed(let c): return "Upload (\(c))"
        case .deleteFailed(let c): return "Delete (\(c))"
        case .invalidFormat(let m): return "Invalid: \(m)"
        case .decompressionFailed: return "Decompress failed"
        }
    }
}
