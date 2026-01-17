import Foundation
import PDFKit
import UniformTypeIdentifiers

@MainActor
class DocumentService: ObservableObject {
    @Published var songs: [Song] = []
    @Published var isLoading: Bool = false
    var activeSonglist: Songlist?
    
    private let fileManager = FileManager.default
    private let musicDirectory: URL
    private let songsMetadataURL: URL
    private let hasCopiedBundledSongsKey = "hasCopiedBundledSongs"
    
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
                guard ["pdf", "doc", "docx"].contains(ext) else { continue }
                
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
            guard ["pdf", "doc", "docx"].contains(ext) else { return nil }
            let fileName = url.deletingPathExtension().lastPathComponent
            let fullFileName = url.lastPathComponent
            
            // Check if we have saved metadata for this song
            if let saved = savedMetadata.first(where: { $0.fullFileName == fullFileName }) {
                saved.filePath = url
                return saved
            }
            
            // Create new song from file
            let title = fileName.replacingOccurrences(of: "_", with: " ")
            let song = Song(title: title, fileName: fileName, fileExtension: ext, filePath: url)
            if ext == "pdf", let doc = PDFDocument(url: url) {
                song.pageCount = doc.pageCount
            }
            return song
        }.sorted { $0.title < $1.title }
    }
    
    func importDocument(from url: URL, completion: @escaping (Result<Song, Error>) -> Void) {
        Task {
            do {
                guard url.startAccessingSecurityScopedResource() else {
                    throw NSError(domain: "Access", code: -1)
                }
                defer { url.stopAccessingSecurityScopedResource() }
                
                let fileName = url.lastPathComponent
                let destination = musicDirectory.appendingPathComponent(fileName)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: url, to: destination)
                
                let ext = url.pathExtension.lowercased()
                let name = url.deletingPathExtension().lastPathComponent
                let song = Song(title: name, fileName: name, fileExtension: ext, filePath: destination)
                
                await MainActor.run {
                    songs.append(song)
                    songs.sort { $0.title < $1.title }
                    isLoading = false
                }
                completion(.success(song))
            } catch {
                await MainActor.run { isLoading = false }
                completion(.failure(error))
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
        let destination = musicDirectory.appendingPathComponent(fileName)
        
        // Don't overwrite existing files
        if !fileManager.fileExists(atPath: destination.path) {
            try data.write(to: destination)
        }
        
        // Create song object
        let ext = (fileName as NSString).pathExtension.lowercased()
        let fileNameWithoutExt = (fileName as NSString).deletingPathExtension
        let title = name.isEmpty ? fileNameWithoutExt.replacingOccurrences(of: "_", with: " ") : name
        
        let song = Song(
            title: title,
            fileName: fileNameWithoutExt,
            fileExtension: ext,
            filePath: destination
        )
        
        // Get page count for PDFs
        if ext == "pdf", let doc = PDFDocument(url: destination) {
            song.pageCount = doc.pageCount
        }
        
        // Add to songs array if not already present
        if !songs.contains(where: { $0.fullFileName == fileName }) {
            songs.append(song)
            songs.sort { $0.title < $1.title }
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
}
