import Foundation
import CoreMIDI
import Combine

@MainActor
class MIDIService: ObservableObject {
    @Published var availableSources: [MIDISource] = []
    @Published var availableDestinations: [MIDIDestination] = []
    @Published var isConnected: Bool = false
    @Published var connectedDestination: MIDIDestination?
    
    private var midiClient: MIDIClientRef = 0
    private var outputPort: MIDIPortRef = 0
    
    init() {
        setupMIDI()
        scanDevices()
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
        
        // Send Bank Select MSB (CC 0) if specified
        if let bankMSB = song.midiBankMSB {
            sendControlChange(channel: channel, controller: 0, value: UInt8(bankMSB), to: destination)
        }
        
        // Send Bank Select LSB (CC 32) if specified
        if let bankLSB = song.midiBankLSB {
            sendControlChange(channel: channel, controller: 32, value: UInt8(bankLSB), to: destination)
        }
        
        // Send Program Change
        sendProgramChangeMessage(channel: channel, program: UInt8(program), to: destination)
        
        print("🎹 Sent MIDI Program Change: Ch\(channel + 1) Prog:\(program)")
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
