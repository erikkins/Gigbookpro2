import Foundation

@MainActor
class Songlist: Codable, Identifiable, Equatable, ObservableObject {
    let id: String
    @Published var name: String
    @Published var songIds: [String]  // Store IDs, not copies
    var dateCreated: Date
    var dateModified: Date
    var event: String?
    var venue: String?
    var eventDate: Date?
    var notes: String?
    
    // Transient - not saved, populated at runtime
    weak var documentService: DocumentService?
    
    init(id: String = UUID().uuidString, name: String, songIds: [String] = [],
         event: String? = nil, venue: String? = nil, eventDate: Date? = nil) {
        self.id = id
        self.name = name
        self.songIds = songIds
        self.dateCreated = Date()
        self.dateModified = Date()
        self.event = event
        self.venue = venue
        self.eventDate = eventDate
    }
    
    static func == (lhs: Songlist, rhs: Songlist) -> Bool { lhs.id == rhs.id }
    
    enum CodingKeys: String, CodingKey {
        case id, name, songIds, songs, dateCreated, dateModified, event, venue, eventDate, notes
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        
        // Try to decode songIds first, fall back to extracting IDs from songs array
        if let ids = try? container.decode([String].self, forKey: .songIds) {
            songIds = ids
        } else if let songs = try? container.decode([Song].self, forKey: .songs) {
            // Migration from old format
            songIds = songs.map { $0.id }
        } else {
            songIds = []
        }
        
        dateCreated = try container.decode(Date.self, forKey: .dateCreated)
        dateModified = try container.decode(Date.self, forKey: .dateModified)
        event = try container.decodeIfPresent(String.self, forKey: .event)
        venue = try container.decodeIfPresent(String.self, forKey: .venue)
        eventDate = try container.decodeIfPresent(Date.self, forKey: .eventDate)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(songIds, forKey: .songIds)
        try container.encode(dateCreated, forKey: .dateCreated)
        try container.encode(dateModified, forKey: .dateModified)
        try container.encodeIfPresent(event, forKey: .event)
        try container.encodeIfPresent(venue, forKey: .venue)
        try container.encodeIfPresent(eventDate, forKey: .eventDate)
        try container.encodeIfPresent(notes, forKey: .notes)
    }
}

extension Songlist {
    var songCount: Int { songIds.count }
    
    // Get actual Song objects by looking them up from DocumentService
    var songs: [Song] {
        guard let service = documentService else { return [] }
        return songIds.compactMap { id in
            service.songs.first { $0.id == id }
        }
    }
    
    func song(at index: Int) -> Song? {
        guard index >= 0, index < songIds.count else { return nil }
        return documentService?.songs.first { $0.id == songIds[index] }
    }
    
    func addSong(_ song: Song) {
        if !songIds.contains(song.id) {
            songIds.append(song.id)
            dateModified = Date()
        }
    }
    
    func removeSong(at index: Int) {
        guard index >= 0, index < songIds.count else { return }
        songIds.remove(at: index)
        dateModified = Date()
    }
    
    func removeSong(_ song: Song) {
        songIds.removeAll { $0 == song.id }
        dateModified = Date()
    }
    
    func moveSong(from source: IndexSet, to destination: Int) {
        songIds.move(fromOffsets: source, toOffset: destination)
        dateModified = Date()
    }
    
    func setSongs(_ songs: [Song]) {
        songIds = songs.map { $0.id }
        dateModified = Date()
    }
}
