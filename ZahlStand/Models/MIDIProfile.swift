import Foundation

// MARK: - MIDI Instrument Type

enum MIDIInstrumentType: String, Codable, CaseIterable, Identifiable {
    case keyboard
    case guitar
    case bass
    case synth
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .keyboard: return "Keyboard"
        case .guitar: return "Guitar"
        case .bass: return "Bass"
        case .synth: return "Synth"
        case .custom: return "Custom"
        }
    }

    var iconName: String {
        switch self {
        case .keyboard: return "pianokeys"
        case .guitar: return "guitars"
        case .bass: return "waveform"
        case .synth: return "waveform.path"
        case .custom: return "slider.horizontal.3"
        }
    }
}

// MARK: - MIDI Profile

struct MIDIProfile: Codable, Equatable, Identifiable {
    var id: String
    var instrumentType: MIDIInstrumentType
    var channel: Int?           // 0-15 (displayed as 1-16)
    var programNumber: Int?     // 0-127
    var bankMSB: Int?           // 0-127 (bank select MSB - CC 0)
    var bankLSB: Int?           // 0-127 (bank select LSB - CC 32)
    var label: String?          // Optional custom label

    init(id: String = UUID().uuidString,
         instrumentType: MIDIInstrumentType,
         channel: Int? = nil,
         programNumber: Int? = nil,
         bankMSB: Int? = nil,
         bankLSB: Int? = nil,
         label: String? = nil) {
        self.id = id
        self.instrumentType = instrumentType
        self.channel = channel
        self.programNumber = programNumber
        self.bankMSB = bankMSB
        self.bankLSB = bankLSB
        self.label = label
    }

    var hasProgramChange: Bool {
        programNumber != nil
    }

    var description: String {
        guard let program = programNumber else { return "Not configured" }
        let ch = (channel ?? 0) + 1
        if let msb = bankMSB, let lsb = bankLSB {
            return "Ch\(ch) Bank:\(msb)/\(lsb) Prog:\(program)"
        } else if let msb = bankMSB {
            return "Ch\(ch) Bank:\(msb) Prog:\(program)"
        }
        return "Ch\(ch) Prog:\(program)"
    }

    /// Create a profile from legacy flat MIDI fields (for migration)
    static func fromLegacy(channel: Int?, program: Int?, bankMSB: Int?, bankLSB: Int?,
                          instrumentType: MIDIInstrumentType = .keyboard) -> MIDIProfile? {
        guard program != nil else { return nil }
        return MIDIProfile(
            instrumentType: instrumentType,
            channel: channel,
            programNumber: program,
            bankMSB: bankMSB,
            bankLSB: bankLSB
        )
    }
}
