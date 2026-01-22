import Foundation

// MARK: - Local MIDI Override

/// Represents local MIDI settings for a song that are device-specific and never sync
struct LocalMIDIOverride: Codable, Equatable {
    /// Keyed by filename (cross-device stable identifier)
    let songFileName: String
    /// MIDI profiles for different instruments
    var profiles: [MIDIProfile]
    /// When this override was last modified
    var lastModified: Date

    init(songFileName: String, profiles: [MIDIProfile] = [], lastModified: Date = Date()) {
        self.songFileName = songFileName
        self.profiles = profiles
        self.lastModified = lastModified
    }

    /// Get profile for a specific instrument type
    func profile(for type: MIDIInstrumentType) -> MIDIProfile? {
        profiles.first { $0.instrumentType == type }
    }

    /// Set or update profile for an instrument type
    mutating func setProfile(_ profile: MIDIProfile) {
        if let index = profiles.firstIndex(where: { $0.instrumentType == profile.instrumentType }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
        lastModified = Date()
    }

    /// Remove profile for an instrument type
    mutating func removeProfile(for type: MIDIInstrumentType) {
        profiles.removeAll { $0.instrumentType == type }
        lastModified = Date()
    }
}

// MARK: - Local MIDI Overrides Store

/// Container for all local MIDI overrides, keyed by song filename
struct LocalMIDIOverridesStore: Codable {
    var overrides: [String: LocalMIDIOverride]

    init(overrides: [String: LocalMIDIOverride] = [:]) {
        self.overrides = overrides
    }

    /// Get override for a song by filename
    func override(for fileName: String) -> LocalMIDIOverride? {
        overrides[fileName]
    }

    /// Set override for a song
    mutating func setOverride(_ override: LocalMIDIOverride) {
        overrides[override.songFileName] = override
    }

    /// Remove override for a song
    mutating func removeOverride(for fileName: String) {
        overrides.removeValue(forKey: fileName)
    }

    /// Check if override exists for a song
    func hasOverride(for fileName: String) -> Bool {
        overrides[fileName] != nil
    }
}
