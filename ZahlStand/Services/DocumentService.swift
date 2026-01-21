import Foundation
import PDFKit
import UniformTypeIdentifiers

@MainActor
class DocumentService: ObservableObject {
    @Published var songs: [Song] = []
    @Published var isLoading: Bool = false
    @Published var isMigrating: Bool = false
    @Published var migrationProgress: Double = 0
    @Published var migrationStatus: String = ""
    @Published var migrationError: String?
    var activeSonglist: Songlist?

    private let fileManager = FileManager.default
    private let musicDirectory: URL
    private let songsMetadataURL: URL
    private let hasCopiedBundledSongsKey = "hasCopiedBundledSongs"
    private let hasMigratedWordFilesKey = "hasMigratedWordFiles"
    
    init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        self.musicDirectory = docs.appendingPathComponent("Music", isDirectory: true)
        self.songsMetadataURL = docs.appendingPathComponent("songs_metadata.json")
        createDirectoriesIfNeeded()
        loadSongs()
    }
    
    private func createDirectoriesIfNeeded() {
        try? fileManager.createDirectory(at: musicDirectory, withIntermediateDirectories: true)
    }
    
    /// Copy bundled song files from app bundle to Documents on first launch
    func copyBundledSongsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: hasCopiedBundledSongsKey) else { return }

        // Look for bundled songs in the app bundle's BundledSongs folder
        guard let bundledSongsURL = Bundle.main.resourceURL?.appendingPathComponent("BundledSongs") else {
            print("⚠️ No BundledSongs folder found in bundle")
            defaults.set(true, forKey: hasCopiedBundledSongsKey)
            return
        }

        guard fileManager.fileExists(atPath: bundledSongsURL.path) else {
            print("⚠️ BundledSongs folder doesn't exist at: \(bundledSongsURL.path)")
            defaults.set(true, forKey: hasCopiedBundledSongsKey)
            return
        }

        do {
            let files = try fileManager.contentsOfDirectory(at: bundledSongsURL, includingPropertiesForKeys: nil)
            var copiedCount = 0

            for fileURL in files {
                let ext = fileURL.pathExtension.lowercased()
                // Only copy PDFs - bundled Word files should be pre-converted
                guard ext == "pdf" else { continue }

                let destURL = musicDirectory.appendingPathComponent(fileURL.lastPathComponent)

                if !fileManager.fileExists(atPath: destURL.path) {
                    try fileManager.copyItem(at: fileURL, to: destURL)
                    copiedCount += 1
                }
            }

            print("✅ Copied \(copiedCount) bundled songs to Documents/Music")
            defaults.set(true, forKey: hasCopiedBundledSongsKey)

            // Reload songs after copying
            loadSongs()
        } catch {
            print("❌ Error copying bundled songs: \(error)")
        }
    }
    
    func loadSongs() {
        isLoading = true
        defer { isLoading = false }

        // Load saved metadata
        let savedMetadata = loadSongsMetadata()

        guard let fileURLs = try? fileManager.contentsOfDirectory(
            at: musicDirectory, includingPropertiesForKeys: [.nameKey],
            options: .skipsHiddenFiles) else { return }

        songs = fileURLs.compactMap { url in
            let ext = url.pathExtension.lowercased()
            // Only load PDFs - Word files should be migrated
            guard ext == "pdf" else { return nil }
            let fileName = url.deletingPathExtension().lastPathComponent
            let fullFileName = url.lastPathComponent

            // Check if we have saved metadata for this song (try both PDF and Word extensions)
            if let saved = savedMetadata.first(where: {
                $0.fullFileName == fullFileName ||
                $0.fileName == fileName  // Match by base name for migrated files
            }) {
                saved.filePath = url
                saved.fileExtension = ext  // Update extension in case it was migrated
                return saved
            }

            // Create new song from file
            let title = fileName.replacingOccurrences(of: "_", with: " ")
            let song = Song(title: title, fileName: fileName, fileExtension: ext, filePath: url)
            if let doc = PDFDocument(url: url) {
                song.pageCount = doc.pageCount
            }
            return song
        }
        songs = sortedSongs(songs)
    }
    
    func importDocument(from url: URL, completion: @escaping (Result<Song, Error>) -> Void) {
        Task {
            do {
                // Try security-scoped access (for document picker), but don't require it (for AirDrop)
                let hasSecurityAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasSecurityAccess {
                        url.stopAccessingSecurityScopedResource()
                    }
                }

                let originalExt = url.pathExtension.lowercased()
                let baseName = url.deletingPathExtension().lastPathComponent
                let title = baseName.replacingOccurrences(of: "_", with: " ")

                var finalDestination: URL
                var finalExt: String

                if ["doc", "docx"].contains(originalExt) {
                    // Copy Word file temporarily, convert to PDF
                    let tempDestination = musicDirectory.appendingPathComponent(url.lastPathComponent)
                    if fileManager.fileExists(atPath: tempDestination.path) {
                        try fileManager.removeItem(at: tempDestination)
                    }
                    try fileManager.copyItem(at: url, to: tempDestination)

                    // Convert to PDF
                    guard let pdfData = await WordToPDFConverter.shared.convert(url: tempDestination) else {
                        try? fileManager.removeItem(at: tempDestination)
                        throw DocumentError.conversionFailed("Failed to convert Word document to PDF")
                    }

                    // Save PDF
                    finalDestination = musicDirectory.appendingPathComponent("\(baseName).pdf")
                    if fileManager.fileExists(atPath: finalDestination.path) {
                        try fileManager.removeItem(at: finalDestination)
                    }
                    try pdfData.write(to: finalDestination)

                    // Remove temp Word file
                    try? fileManager.removeItem(at: tempDestination)
                    finalExt = "pdf"
                } else {
                    // PDF - just copy
                    finalDestination = musicDirectory.appendingPathComponent(url.lastPathComponent)
                    if fileManager.fileExists(atPath: finalDestination.path) {
                        try fileManager.removeItem(at: finalDestination)
                    }
                    try fileManager.copyItem(at: url, to: finalDestination)
                    finalExt = originalExt
                }

                let song = Song(title: title, fileName: baseName, fileExtension: finalExt, filePath: finalDestination)

                // Get page count for PDFs
                if let doc = PDFDocument(url: finalDestination) {
                    song.pageCount = doc.pageCount
                }

                await MainActor.run {
                    songs.append(song)
                    sortSongsInPlace()
                    saveSongsMetadata()
                    isLoading = false
                }
                completion(.success(song))
            } catch {
                await MainActor.run { isLoading = false }
                completion(.failure(error))
            }
        }
    }

    enum DocumentError: LocalizedError {
        case conversionFailed(String)

        var errorDescription: String? {
            switch self {
            case .conversionFailed(let message): return message
            }
        }
    }
    
    func deleteSong(_ song: Song) throws {
        guard let filePath = song.filePath else { return }
        try fileManager.removeItem(at: filePath)
        songs.removeAll { $0.id == song.id }
        saveSongsMetadata()
    }
    
    func loadPDFDocument(for song: Song) -> PDFDocument? {
        guard song.isPDF, let filePath = song.filePath else { return nil }
        return PDFDocument(url: filePath)
    }
    
    func searchSongs(query: String) -> [Song] {
        guard !query.isEmpty else { return songs }
        let lowercased = query.lowercased()
        return songs.filter {
            $0.title.lowercased().contains(lowercased) ||
            ($0.artist?.lowercased().contains(lowercased) ?? false)
        }
    }
    
    func addSongToActiveSonglist(_ song: Song) {
        guard let songlist = activeSonglist else { return }
        songlist.addSong(song)
    }
    
    // MARK: - Import Embedded File (from Legacy Azure blobs)

    func importEmbeddedFile(name: String, fileName: String, data: Data) async throws -> Song {
        let originalExt = (fileName as NSString).pathExtension.lowercased()
        let fileNameWithoutExt = (fileName as NSString).deletingPathExtension
        let title = name.isEmpty ? fileNameWithoutExt.replacingOccurrences(of: "_", with: " ") : name

        var finalDestination: URL
        var finalExt: String
        let pdfFileName = "\(fileNameWithoutExt).pdf"

        // Check if PDF version already exists
        let pdfDestination = musicDirectory.appendingPathComponent(pdfFileName)
        if fileManager.fileExists(atPath: pdfDestination.path) {
            finalDestination = pdfDestination
            finalExt = "pdf"
        } else if ["doc", "docx"].contains(originalExt) {
            // Write Word file temporarily
            let tempDestination = musicDirectory.appendingPathComponent(fileName)
            try data.write(to: tempDestination)

            // Convert to PDF
            guard let pdfData = await WordToPDFConverter.shared.convert(url: tempDestination) else {
                try? fileManager.removeItem(at: tempDestination)
                throw DocumentError.conversionFailed("Failed to convert Word document to PDF: \(fileName)")
            }

            // Save PDF
            try pdfData.write(to: pdfDestination)

            // Remove temp Word file
            try? fileManager.removeItem(at: tempDestination)

            finalDestination = pdfDestination
            finalExt = "pdf"
        } else {
            // PDF - write directly
            let destination = musicDirectory.appendingPathComponent(fileName)
            if !fileManager.fileExists(atPath: destination.path) {
                try data.write(to: destination)
            }
            finalDestination = destination
            finalExt = originalExt
        }

        let song = Song(
            title: title,
            fileName: fileNameWithoutExt,
            fileExtension: finalExt,
            filePath: finalDestination
        )

        // Get page count for PDFs
        if let doc = PDFDocument(url: finalDestination) {
            song.pageCount = doc.pageCount
        }

        // Add to songs array if not already present (check by base filename)
        if !songs.contains(where: { $0.fileName == fileNameWithoutExt }) {
            songs.append(song)
            sortSongsInPlace()
        }

        // Save song metadata
        saveSong(song)

        return song
    }
    
    // MARK: - Song Metadata Persistence
    
    func saveSong(_ song: Song) {
        saveSongsMetadata()
    }
    
    private func saveSongsMetadata() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(songs)
            try data.write(to: songsMetadataURL)
        } catch {
            print("❌ Failed to save songs metadata: \(error)")
        }
    }
    
    private func loadSongsMetadata() -> [Song] {
        guard fileManager.fileExists(atPath: songsMetadataURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: songsMetadataURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([Song].self, from: data)
        } catch {
            print("❌ Failed to load songs metadata: \(error)")
            return []
        }
    }

    // MARK: - Word to PDF Migration

    /// Returns true if migration is needed
    func needsWordFileMigration() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: hasMigratedWordFilesKey) { return false }

        // Check if any Word files exist in the music directory
        guard let files = try? fileManager.contentsOfDirectory(at: musicDirectory, includingPropertiesForKeys: nil) else {
            return false
        }

        return files.contains { url in
            let ext = url.pathExtension.lowercased()
            return ext == "doc" || ext == "docx"
        }
    }

    /// Migrate all Word files to PDF
    func migrateWordFilesToPDF() async {
        let defaults = UserDefaults.standard

        guard let files = try? fileManager.contentsOfDirectory(at: musicDirectory, includingPropertiesForKeys: nil) else {
            defaults.set(true, forKey: hasMigratedWordFilesKey)
            return
        }

        let wordFiles = files.filter { url in
            let ext = url.pathExtension.lowercased()
            return ext == "doc" || ext == "docx"
        }

        if wordFiles.isEmpty {
            defaults.set(true, forKey: hasMigratedWordFilesKey)
            return
        }

        isMigrating = true
        migrationProgress = 0
        migrationError = nil

        var convertedCount = 0
        var failedFiles: [String] = []

        for (index, wordURL) in wordFiles.enumerated() {
            let fileName = wordURL.deletingPathExtension().lastPathComponent
            migrationStatus = "Converting: \(fileName)"

            let pdfURL = musicDirectory.appendingPathComponent("\(fileName).pdf")

            // Skip if PDF already exists
            if fileManager.fileExists(atPath: pdfURL.path) {
                // Just delete the Word file
                try? fileManager.removeItem(at: wordURL)
                convertedCount += 1
            } else {
                // Convert to PDF
                if let pdfData = await WordToPDFConverter.shared.convert(url: wordURL) {
                    do {
                        try pdfData.write(to: pdfURL)
                        try fileManager.removeItem(at: wordURL)
                        convertedCount += 1

                        // Update any existing song metadata
                        if let song = songs.first(where: { $0.fileName == fileName }) {
                            song.fileExtension = "pdf"
                            song.filePath = pdfURL
                            if let doc = PDFDocument(url: pdfURL) {
                                song.pageCount = doc.pageCount
                            }
                        }
                    } catch {
                        failedFiles.append("\(fileName): \(error.localizedDescription)")
                    }
                } else {
                    failedFiles.append("\(fileName): Conversion failed")
                }
            }

            migrationProgress = Double(index + 1) / Double(wordFiles.count)
        }

        // Save updated metadata
        saveSongsMetadata()

        // Reload songs to pick up any new PDFs
        loadSongs()

        migrationStatus = "Migration complete"
        isMigrating = false

        if !failedFiles.isEmpty {
            migrationError = "Failed to convert:\n" + failedFiles.joined(separator: "\n")
        }

        defaults.set(true, forKey: hasMigratedWordFilesKey)
    }

    // MARK: - Sorting

    /// Sorts songs case-insensitively, ignoring leading underscores/non-letter characters
    func sortedSongs(_ songs: [Song]) -> [Song] {
        songs.sorted { compareSongTitles($0.title, $1.title) }
    }

    func sortSongsInPlace() {
        songs.sort { compareSongTitles($0.title, $1.title) }
    }

    private func compareSongTitles(_ a: String, _ b: String) -> Bool {
        let normalizedA = sortableTitle(a)
        let normalizedB = sortableTitle(b)
        return normalizedA.localizedCaseInsensitiveCompare(normalizedB) == .orderedAscending
    }

    private func sortableTitle(_ title: String) -> String {
        // Strip leading underscores, spaces, and punctuation (but keep numbers)
        var result = title
        while let first = result.first, !first.isLetter && !first.isNumber {
            result.removeFirst()
        }
        return result.isEmpty ? title : result
    }
}
