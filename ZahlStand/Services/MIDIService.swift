import Foundation
import CoreMIDI
import Combine

// MARK: - Custom MIDI Patch

struct MIDIPatch: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var programNumber: Int  // 0-127

    init(id: UUID = UUID(), name: String, programNumber: Int) {
        self.id = id
        self.name = name
        self.programNumber = max(0, min(127, programNumber))
    }
}

// MARK: - MIDI Service

@MainActor
class MIDIService: ObservableObject {
    @Published var availableSources: [MIDISource] = []
    @Published var availableDestinations: [MIDIDestination] = []
    @Published var isConnected: Bool = false
    @Published var connectedDestination: MIDIDestination?

    /// Nord Stage mode: sends hardcoded Bank MSB=0, LSB=3 before program changes
    @Published var nordStageMode: Bool {
        didSet {
            UserDefaults.standard.set(nordStageMode, forKey: "nordStageMode")
        }
    }

    /// Custom patches for Nord Stage or other instruments
    @Published var customPatches: [MIDIPatch] = [] {
        didSet {
            saveCustomPatches()
        }
    }

    private var midiClient: MIDIClientRef = 0
    private var outputPort: MIDIPortRef = 0

    init() {
        self.nordStageMode = UserDefaults.standard.bool(forKey: "nordStageMode")
        self.customPatches = Self.loadCustomPatches()
        setupMIDI()
        scanDevices()
    }

    // MARK: - Custom Patches Persistence

    private func saveCustomPatches() {
        if let data = try? JSONEncoder().encode(customPatches) {
            UserDefaults.standard.set(data, forKey: "customMIDIPatches")
        }
    }

    private static func loadCustomPatches() -> [MIDIPatch] {
        guard let data = UserDefaults.standard.data(forKey: "customMIDIPatches"),
              let patches = try? JSONDecoder().decode([MIDIPatch].self, from: data),
              !patches.isEmpty else {
            return defaultNordPatches()
        }
        return patches
    }

    /// Default Nord Stage 2EX patches (Bank D, Pages 1-6)
    static func defaultNordPatches() -> [MIDIPatch] {
        [
            // Page 1 (D:1:1-5) - PC 0-4
            MIDIPatch(name: "Italian Grand", programNumber: 0),
            MIDIPatch(name: "Easy Does It", programNumber: 1),
            MIDIPatch(name: "Rock Organ", programNumber: 2),
            MIDIPatch(name: "Rays Vox & Bass", programNumber: 3),
            MIDIPatch(name: "MkV ClsIdeal", programNumber: 4),
            // Page 2 (D:2:1-5) - PC 5-9
            MIDIPatch(name: "Clavinet A", programNumber: 5),
            MIDIPatch(name: "Accordion", programNumber: 6),
            MIDIPatch(name: "Piradzin", programNumber: 7),
            MIDIPatch(name: "Juku Prata", programNumber: 8),
            MIDIPatch(name: "Nodzisa Blazma", programNumber: 9),
            // Page 3 (D:3:1-5) - PC 10-14
            MIDIPatch(name: "Tapec Jau", programNumber: 10),
            MIDIPatch(name: "Starp Divam", programNumber: 11),
            MIDIPatch(name: "Tenor Sax", programNumber: 12),
            MIDIPatch(name: "Vigilantes", programNumber: 13),
            MIDIPatch(name: "You Got It", programNumber: 14),
            // Page 4 (D:4:1-5) - PC 15-19
            MIDIPatch(name: "Putni", programNumber: 15),
            MIDIPatch(name: "Quartet-Orch", programNumber: 16),
            MIDIPatch(name: "Caroline Intro", programNumber: 17),
            MIDIPatch(name: "Caroline Verse", programNumber: 18),
            MIDIPatch(name: "Caroline Chorus", programNumber: 19),
            // Page 5 (D:5:1-5) - PC 20-24
            MIDIPatch(name: "Marimba", programNumber: 20),
            MIDIPatch(name: "Sexy Thing", programNumber: 21),
            MIDIPatch(name: "Suspicious", programNumber: 22),
            MIDIPatch(name: "DPMS EP Mk V", programNumber: 23),
            MIDIPatch(name: "DPMS GrandP", programNumber: 24),
            // Page 6 (D:6:1) - PC 25
            MIDIPatch(name: "You Don't Know", programNumber: 25),
        ]
    }

    func addPatch(_ patch: MIDIPatch) {
        customPatches.append(patch)
    }

    func updatePatch(_ patch: MIDIPatch) {
        if let index = customPatches.firstIndex(where: { $0.id == patch.id }) {
            customPatches[index] = patch
        }
    }

    func deletePatch(_ patch: MIDIPatch) {
        customPatches.removeAll { $0.id == patch.id }
    }

    func movePatch(from source: IndexSet, to destination: Int) {
        customPatches.move(fromOffsets: source, toOffset: destination)
    }

    func resetPatchesToDefaults() {
        customPatches = Self.defaultNordPatches()
    }
    
    deinit {
        if outputPort != 0 { MIDIPortDispose(outputPort) }
        if midiClient != 0 { MIDIClientDispose(midiClient) }
    }
    
    private func setupMIDI() {
        var status: OSStatus
        status = MIDIClientCreate("ZahlStand" as CFString, nil, nil, &midiClient)
        guard status == noErr else { return }
        status = MIDIOutputPortCreate(midiClient, "Output" as CFString, &outputPort)
        guard status == noErr else { return }
    }
    
    func scanDevices() {
        var destinations: [MIDIDestination] = []
        for i in 0..<MIDIGetNumberOfDestinations() {
            let endpoint = MIDIGetDestination(i)
            if let dest = createMIDIDestination(from: endpoint) {
                destinations.append(dest)
            }
        }
        availableDestinations = destinations
        
        // Also scan sources for display (though we don't use them for input)
        var sources: [MIDISource] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let endpoint = MIDIGetSource(i)
            if let source = createMIDISource(from: endpoint) {
                sources.append(source)
            }
        }
        availableSources = sources
    }
    
    private func createMIDISource(from endpoint: MIDIEndpointRef) -> MIDISource? {
        var name: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name) == noErr,
              let cfName = name?.takeRetainedValue() else { return nil }
        return MIDISource(endpoint: endpoint, name: cfName as String)
    }
    
    private func createMIDIDestination(from endpoint: MIDIEndpointRef) -> MIDIDestination? {
        var name: Unmanaged<CFString>?
        guard MIDIObjectGetStringProperty(endpoint, kMIDIPropertyName, &name) == noErr,
              let cfName = name?.takeRetainedValue() else { return nil }
        return MIDIDestination(endpoint: endpoint, name: cfName as String)
    }
    
    func connectToDestination(_ destination: MIDIDestination) {
        connectedDestination = destination
        isConnected = true
    }
    
    func disconnect() {
        connectedDestination = nil
        isConnected = false
    }
    
    // MARK: - Send MIDI Program Change

    /// Send program change for a song to change the patch on connected instrument
    func sendProgramChange(for song: Song) {
        guard let destination = connectedDestination,
              let program = song.midiProgramNumber else { return }

        let channel = UInt8(song.midiChannel ?? 0)

        if nordStageMode {
            // Nord Stage 2EX mode: always send Bank MSB=0, LSB=3
            sendControlChange(channel: channel, controller: 0, value: 0, to: destination)
            sendControlChange(channel: channel, controller: 32, value: 3, to: destination)
            print("🎹 Nord Stage mode: Sent Bank MSB=0, LSB=3")
        } else {
            // Standard mode: use song's bank settings if specified
            if let bankMSB = song.midiBankMSB {
                sendControlChange(channel: channel, controller: 0, value: UInt8(bankMSB), to: destination)
            }
            if let bankLSB = song.midiBankLSB {
                sendControlChange(channel: channel, controller: 32, value: UInt8(bankLSB), to: destination)
            }
        }

        // Send Program Change
        sendProgramChangeMessage(channel: channel, program: UInt8(program), to: destination)

        print("🎹 Sent MIDI Program Change: Ch\(channel + 1) Prog:\(program)\(nordStageMode ? " (Nord Stage)" : "")")
    }
    
    private func sendProgramChangeMessage(channel: UInt8, program: UInt8, to destination: MIDIDestination) {
        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        
        // Program Change: 0xC0 | channel, program
        let programChange: [UInt8] = [0xC0 | (channel & 0x0F), program & 0x7F]
        
        programChange.withUnsafeBufferPointer { buffer in
            packet = MIDIPacketListAdd(&packetList, 1024, packet, 0, buffer.count, buffer.baseAddress!)
        }
        
        MIDISend(outputPort, destination.endpoint, &packetList)
    }
    
    private func sendControlChange(channel: UInt8, controller: UInt8, value: UInt8, to destination: MIDIDestination) {
        var packetList = MIDIPacketList()
        var packet = MIDIPacketListInit(&packetList)
        
        // Control Change: 0xB0 | channel, controller, value
        let controlChange: [UInt8] = [0xB0 | (channel & 0x0F), controller & 0x7F, value & 0x7F]
        
        controlChange.withUnsafeBufferPointer { buffer in
            packet = MIDIPacketListAdd(&packetList, 1024, packet, 0, buffer.count, buffer.baseAddress!)
        }
        
        MIDISend(outputPort, destination.endpoint, &packetList)
    }
}

struct MIDISource: Identifiable {
    let id = UUID()
    let endpoint: MIDIEndpointRef
    let name: String
}

struct MIDIDestination: Identifiable, Equatable {
    let id = UUID()
    let endpoint: MIDIEndpointRef
    let name: String
    
    static func == (lhs: MIDIDestination, rhs: MIDIDestination) -> Bool {
        lhs.endpoint == rhs.endpoint
    }
}
