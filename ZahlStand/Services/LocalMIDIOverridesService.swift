import Foundation

// MARK: - Local MIDI Overrides Service

/// Service for managing device-local MIDI settings that never sync to cloud
@MainActor
class LocalMIDIOverridesService: ObservableObject {
    @Published var store: LocalMIDIOverridesStore

    /// Whether to use local overrides when sending MIDI (persisted in UserDefaults)
    @Published var useLocalOverrides: Bool {
        didSet {
            UserDefaults.standard.set(useLocalOverrides, forKey: "useLocalMIDIOverrides")
        }
    }

    /// The currently active instrument type for MIDI (persisted in UserDefaults)
    @Published var activeInstrumentType: MIDIInstrumentType {
        didSet {
            UserDefaults.standard.set(activeInstrumentType.rawValue, forKey: "activeMIDIInstrumentType")
        }
    }

    private let storageURL: URL

    init() {
        // Load preferences from UserDefaults
        self.useLocalOverrides = UserDefaults.standard.bool(forKey: "useLocalMIDIOverrides")

        if let savedType = UserDefaults.standard.string(forKey: "activeMIDIInstrumentType"),
           let type = MIDIInstrumentType(rawValue: savedType) {
            self.activeInstrumentType = type
        } else {
            self.activeInstrumentType = .keyboard
        }

        // Setup storage path
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.storageURL = documentsPath.appendingPathComponent("local_midi_overrides.json")

        // Load store
        self.store = LocalMIDIOverridesStore()
        loadStore()
    }

    // MARK: - Persistence

    private func loadStore() {
        guard FileManager.default.fileExists(atPath: storageURL.path) else { return }

        do {
            let data = try Data(contentsOf: storageURL)
            store = try JSONDecoder().decode(LocalMIDIOverridesStore.self, from: data)
            print("📂 Loaded \(store.overrides.count) local MIDI overrides")
        } catch {
            print("⚠️ Failed to load local MIDI overrides: \(error.localizedDescription)")
        }
    }

    private func saveStore() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(store)
            try data.write(to: storageURL, options: .atomicWrite)
        } catch {
            print("⚠️ Failed to save local MIDI overrides: \(error.localizedDescription)")
        }
    }

    // MARK: - Query Methods

    /// Get the effective MIDI profile for a song (considers local override and active instrument)
    func effectiveProfile(for song: Song) -> MIDIProfile? {
        // First check for local override if enabled
        if useLocalOverrides, let override = store.override(for: song.fullFileName) {
            if let profile = override.profile(for: activeInstrumentType), profile.hasProgramChange {
                return profile
            }
        }

        // Fall back to song's stored profile for active instrument
        return song.midiProfile(for: activeInstrumentType)
    }

    /// Check if a song has a local override
    func hasLocalOverride(for song: Song) -> Bool {
        store.hasOverride(for: song.fullFileName)
    }

    /// Get local override for a song
    func localOverride(for song: Song) -> LocalMIDIOverride? {
        store.override(for: song.fullFileName)
    }

    // MARK: - Modification Methods

    /// Set or update a local override for a song
    func setOverride(_ override: LocalMIDIOverride) {
        store.setOverride(override)
        saveStore()
    }

    /// Set a profile within a song's local override
    func setLocalProfile(_ profile: MIDIProfile, for song: Song) {
        var override = store.override(for: song.fullFileName) ?? LocalMIDIOverride(songFileName: song.fullFileName)
        override.setProfile(profile)
        store.setOverride(override)
        saveStore()
    }

    /// Remove local override for a song (resets to songlist defaults)
    func resetToSonglistDefaults(for song: Song) {
        store.removeOverride(for: song.fullFileName)
        saveStore()
    }

    /// Push local override settings to a song's shared profiles
    func pushOverrideToSong(_ song: Song, documentService: DocumentService) {
        guard let override = store.override(for: song.fullFileName) else { return }

        // Copy all local profiles to the song's shared profiles
        for profile in override.profiles {
            song.setMIDIProfile(profile)
        }

        // Save the song
        documentService.saveSong(song)
        print("✅ Pushed local MIDI settings to songlist for: \(song.title)")
    }

    /// Import song's shared profiles as local overrides
    func importFromSong(_ song: Song) {
        guard song.hasAnyMIDIProfile else { return }

        var override = LocalMIDIOverride(songFileName: song.fullFileName)
        override.profiles = song.midiProfiles
        store.setOverride(override)
        saveStore()
    }
}
