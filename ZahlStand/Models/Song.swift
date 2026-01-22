import Foundation

@MainActor
class Song: Codable, Identifiable, Equatable, ObservableObject {
    let id: String
    @Published var title: String
    @Published var artist: String?
    var fileName: String
    var fileExtension: String
    var filePath: URL?
    var dateAdded: Date
    var lastModified: Date
    @Published var tags: [String]
    @Published var pageCount: Int?
    var duration: TimeInterval?
    var tempo: String?
    var key: String?
    var notes: String?
    
    // MIDI Program Change settings for connected instruments
    @Published var midiChannel: Int?          // 0-15 (displayed as 1-16) - Legacy field
    @Published var midiProgramNumber: Int?    // 0-127 (program/patch number) - Legacy field
    @Published var midiBankMSB: Int?          // 0-127 (bank select MSB - CC 0) - Legacy field
    @Published var midiBankLSB: Int?          // 0-127 (bank select LSB - CC 32) - Legacy field

    // Multi-instrument MIDI profiles (new format)
    @Published var midiProfiles: [MIDIProfile] = []
    
    init(id: String = UUID().uuidString, title: String, fileName: String, 
         fileExtension: String, artist: String? = nil, filePath: URL? = nil) {
        self.id = id
        self.title = title
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.artist = artist
        self.filePath = filePath
        self.dateAdded = Date()
        self.lastModified = Date()
        self.tags = []
    }
    
    static func == (lhs: Song, rhs: Song) -> Bool { lhs.id == rhs.id }
    
    enum CodingKeys: String, CodingKey {
        case id, title, artist, fileName, fileExtension, filePath
        case dateAdded, lastModified, tags, pageCount, duration, tempo, key, notes
        case midiChannel, midiProgramNumber, midiBankMSB, midiBankLSB
        case midiProfiles
    }
    
    required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        artist = try container.decodeIfPresent(String.self, forKey: .artist)
        fileName = try container.decode(String.self, forKey: .fileName)
        fileExtension = try container.decode(String.self, forKey: .fileExtension)
        if let pathString = try container.decodeIfPresent(String.self, forKey: .filePath) {
            filePath = URL(fileURLWithPath: pathString)
        }
        dateAdded = try container.decode(Date.self, forKey: .dateAdded)
        lastModified = try container.decode(Date.self, forKey: .lastModified)
        tags = try container.decode([String].self, forKey: .tags)
        pageCount = try container.decodeIfPresent(Int.self, forKey: .pageCount)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        tempo = try container.decodeIfPresent(String.self, forKey: .tempo)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        notes = try container.decodeIfPresent(String.self, forKey: .notes)
        midiChannel = try container.decodeIfPresent(Int.self, forKey: .midiChannel)
        midiProgramNumber = try container.decodeIfPresent(Int.self, forKey: .midiProgramNumber)
        midiBankMSB = try container.decodeIfPresent(Int.self, forKey: .midiBankMSB)
        midiBankLSB = try container.decodeIfPresent(Int.self, forKey: .midiBankLSB)

        // Decode profiles if present, otherwise migrate from legacy fields
        if let profiles = try container.decodeIfPresent([MIDIProfile].self, forKey: .midiProfiles), !profiles.isEmpty {
            midiProfiles = profiles
        } else if let legacyProfile = MIDIProfile.fromLegacy(
            channel: midiChannel,
            program: midiProgramNumber,
            bankMSB: midiBankMSB,
            bankLSB: midiBankLSB
        ) {
            // Migrate legacy fields to keyboard profile
            midiProfiles = [legacyProfile]
        } else {
            midiProfiles = []
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(artist, forKey: .artist)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(fileExtension, forKey: .fileExtension)
        try container.encodeIfPresent(filePath?.path, forKey: .filePath)
        try container.encode(dateAdded, forKey: .dateAdded)
        try container.encode(lastModified, forKey: .lastModified)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(pageCount, forKey: .pageCount)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(tempo, forKey: .tempo)
        try container.encodeIfPresent(key, forKey: .key)
        try container.encodeIfPresent(notes, forKey: .notes)
        // Write legacy fields for backward compatibility (use keyboard profile if available)
        let legacyProfile = midiProfile(for: .keyboard) ?? primaryMIDIProfile
        try container.encodeIfPresent(legacyProfile?.channel ?? midiChannel, forKey: .midiChannel)
        try container.encodeIfPresent(legacyProfile?.programNumber ?? midiProgramNumber, forKey: .midiProgramNumber)
        try container.encodeIfPresent(legacyProfile?.bankMSB ?? midiBankMSB, forKey: .midiBankMSB)
        try container.encodeIfPresent(legacyProfile?.bankLSB ?? midiBankLSB, forKey: .midiBankLSB)

        // Write new format profiles
        if !midiProfiles.isEmpty {
            try container.encode(midiProfiles, forKey: .midiProfiles)
        }
    }
    
    // MARK: - MIDI Profile Methods

    /// Check if song has MIDI program change configured (legacy or new format)
    var hasMIDIProgramChange: Bool {
        hasAnyMIDIProfile || midiProgramNumber != nil
    }

    /// Check if song has any MIDI profiles configured
    var hasAnyMIDIProfile: Bool {
        !midiProfiles.isEmpty && midiProfiles.contains { $0.hasProgramChange }
    }

    /// Get the primary (first) MIDI profile
    var primaryMIDIProfile: MIDIProfile? {
        midiProfiles.first { $0.hasProgramChange }
    }

    /// Get MIDI profile for a specific instrument type
    func midiProfile(for type: MIDIInstrumentType) -> MIDIProfile? {
        midiProfiles.first { $0.instrumentType == type && $0.hasProgramChange }
    }

    /// Set or update a MIDI profile for an instrument type
    func setMIDIProfile(_ profile: MIDIProfile) {
        if let index = midiProfiles.firstIndex(where: { $0.instrumentType == profile.instrumentType }) {
            midiProfiles[index] = profile
        } else {
            midiProfiles.append(profile)
        }

        // Also update legacy fields for keyboard profile
        if profile.instrumentType == .keyboard {
            midiChannel = profile.channel
            midiProgramNumber = profile.programNumber
            midiBankMSB = profile.bankMSB
            midiBankLSB = profile.bankLSB
        }

        lastModified = Date()
    }

    /// Remove MIDI profile for an instrument type
    func removeMIDIProfile(for type: MIDIInstrumentType) {
        midiProfiles.removeAll { $0.instrumentType == type }
        if type == .keyboard {
            midiChannel = nil
            midiProgramNumber = nil
            midiBankMSB = nil
            midiBankLSB = nil
        }
        lastModified = Date()
    }

    /// Clear all MIDI profiles
    func clearAllMIDIProfiles() {
        midiProfiles.removeAll()
        midiChannel = nil
        midiProgramNumber = nil
        midiBankMSB = nil
        midiBankLSB = nil
        lastModified = Date()
    }

    // Generate MIDI program change description (uses primary profile or legacy fields)
    var midiProgramDescription: String? {
        if let profile = primaryMIDIProfile {
            return profile.description
        }
        guard let program = midiProgramNumber else { return nil }
        let channel = (midiChannel ?? 0) + 1
        if let msb = midiBankMSB, let lsb = midiBankLSB {
            return "Ch\(channel) Bank:\(msb)/\(lsb) Prog:\(program)"
        } else if let msb = midiBankMSB {
            return "Ch\(channel) Bank:\(msb) Prog:\(program)"
        }
        return "Ch\(channel) Prog:\(program)"
    }
}

extension Song {
    var displayName: String {
        if let artist = artist, !artist.isEmpty { return "\(artist) - \(title)" }
        return title
    }
    var fullFileName: String { "\(fileName).\(fileExtension)" }
    var isPDF: Bool { fileExtension.lowercased() == "pdf" }
    var isWord: Bool { ["doc", "docx"].contains(fileExtension.lowercased()) }

    /// Extracts numeric BPM value from tempo string (e.g., "120 BPM" -> 120)
    var bpmValue: Int? {
        guard let tempo = tempo, !tempo.isEmpty else { return nil }
        let digits = tempo.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        guard let value = Int(digits), value > 0, value <= 300 else { return nil }
        return value
    }
}
