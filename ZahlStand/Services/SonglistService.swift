import Foundation
import Combine

@MainActor
class SonglistService: ObservableObject {
    @Published var songlists: [Songlist] = []
    @Published var activeSonglist: Songlist?
    
    private let fileManager = FileManager.default
    private var songlistsDirectory: URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Songlists", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    weak var documentService: DocumentService?
    
    init() {
        loadSonglists()
    }
    
    func loadSonglists() {
        do {
            let files = try fileManager.contentsOfDirectory(at: songlistsDirectory, includingPropertiesForKeys: nil)
            songlists = files.filter { $0.pathExtension == "json" }.compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let songlist = try? JSONDecoder().decode(Songlist.self, from: data) else { return nil }
                songlist.documentService = documentService
                return songlist
            }.sorted { $0.dateModified > $1.dateModified }
            
            // Notify views of change
            objectWillChange.send()
        } catch {
            print("Error loading songlists: \(error)")
        }
    }
    
    func saveSonglist(_ songlist: Songlist) throws {
        songlist.documentService = documentService
        let url = songlistsDirectory.appendingPathComponent("\(songlist.id).json")
        let data = try JSONEncoder().encode(songlist)
        try data.write(to: url)
        
        // Reload all songlists to refresh the view
        loadSonglists()
        
        // Update active songlist if it's the one being edited
        if activeSonglist?.id == songlist.id {
            activeSonglist = songlist
        }
    }
    
    func deleteSonglist(_ songlist: Songlist) throws {
        let url = songlistsDirectory.appendingPathComponent("\(songlist.id).json")
        try fileManager.removeItem(at: url)
        songlists.removeAll { $0.id == songlist.id }
        if activeSonglist?.id == songlist.id { activeSonglist = nil }
        
        // Notify views
        objectWillChange.send()
    }
    
    func setActiveSonglist(_ songlist: Songlist?) {
        songlist?.documentService = documentService
        activeSonglist = songlist
    }
    
    func createSonglist(name: String, songs: [Song] = [], event: String? = nil, venue: String? = nil) -> Songlist {
        let songlist = Songlist(name: name, songIds: songs.map { $0.id }, event: event, venue: venue)
        songlist.documentService = documentService
        try? saveSonglist(songlist)
        return songlist
    }
}
