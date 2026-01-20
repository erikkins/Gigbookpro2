import SwiftUI
import UIKit

// Custom numeric text field that properly shows keyboard
struct NumericTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    
    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField()
        textField.keyboardType = .numberPad
        textField.textAlignment = .right
        textField.placeholder = placeholder
        textField.delegate = context.coordinator
        textField.text = text
        return textField
    }
    
    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UITextFieldDelegate {
        var parent: NumericTextField
        
        init(_ parent: NumericTextField) {
            self.parent = parent
        }
        
        func textFieldDidChangeSelection(_ textField: UITextField) {
            parent.text = textField.text ?? ""
        }
        
        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            // Only allow digits
            let allowedCharacters = CharacterSet.decimalDigits
            let characterSet = CharacterSet(charactersIn: string)
            return allowedCharacters.isSuperset(of: characterSet)
        }
    }
}

struct SongEditorView: View {
    @ObservedObject var song: Song
    @EnvironmentObject var documentService: DocumentService
    @EnvironmentObject var midiService: MIDIService
    @Environment(\.dismiss) var dismiss
    
    @State private var title: String = ""
    @State private var artist: String = ""
    @State private var tempo: String = ""
    @State private var key: String = ""
    @State private var notes: String = ""
    
    // MIDI Settings
    @State private var midiEnabled: Bool = false
    @State private var midiChannelText: String = "1"
    @State private var midiPatchText: String = "0"
    @State private var useBankSelect: Bool = false
    @State private var bankMSBText: String = "0"
    @State private var bankLSBText: String = "0"

    // Tap Tempo
    @State private var tapTimes: [Date] = []
    
    var body: some View {
        NavigationView {
            Form {
                songDetailsSection
                midiSection
                if midiEnabled {
                    if !midiService.customPatches.isEmpty {
                        customPatchesSection
                    }
                    presetsSection
                }
                notesSection
                fileInfoSection
            }
            .navigationTitle("Edit Song")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveChanges() }
                }
            }
            .onAppear { loadSongData() }
        }
    }
    
    // MARK: - Sections
    
    private var songDetailsSection: some View {
        Section {
            TextField("Title", text: $title)
                .autocapitalization(.words)
            TextField("Artist", text: $artist)
                .autocapitalization(.words)
            TextField("Key (e.g., C, Am, G)", text: $key)
                .autocapitalization(.allCharacters)
            HStack {
                TextField("", text: $tempo)
                    .keyboardType(.numberPad)
                    .frame(width: 50)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: tempo) { newValue in
                        // Limit to 3 digits
                        let filtered = newValue.filter { $0.isNumber }
                        if filtered.count > 3 {
                            tempo = String(filtered.prefix(3))
                        } else if filtered != newValue {
                            tempo = filtered
                        }
                    }
                Text("BPM")
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    handleTapTempo()
                } label: {
                    Text("Tap")
                        .font(.subheadline.bold())
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue)
                        .cornerRadius(6)
                }
                .buttonStyle(PlainButtonStyle())
            }
        } header: {
            Text("Song Details")
        }
    }
    
    private var midiSection: some View {
        Section {
            Toggle("Send MIDI Program Change", isOn: $midiEnabled)
            
            if midiEnabled {
                HStack {
                    Text("Channel")
                    Spacer()
                    NumericTextField(text: $midiChannelText, placeholder: "1-16")
                        .frame(width: 60, height: 30)
                }
                
                HStack {
                    Text("Patch")
                    Spacer()
                    NumericTextField(text: $midiPatchText, placeholder: "0-127")
                        .frame(width: 60, height: 30)
                }
                
                if let patch = Int(midiPatchText), patch >= 0, patch < 128 {
                    Text(gmProgramName(patch))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Toggle("Use Bank Select", isOn: $useBankSelect)
                
                if useBankSelect {
                    HStack {
                        Text("Bank MSB")
                        Spacer()
                        NumericTextField(text: $bankMSBText, placeholder: "0-127")
                            .frame(width: 60, height: 30)
                    }
                    
                    HStack {
                        Text("Bank LSB")
                        Spacer()
                        NumericTextField(text: $bankLSBText, placeholder: "0-127")
                            .frame(width: 60, height: 30)
                    }
                }
            }
        } header: {
            Text("MIDI Program Change")
        } footer: {
            Text("When this song is displayed, the app sends a MIDI program change to switch patches.")
        }
    }
    
    private var customPatchesSection: some View {
        Section {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                ForEach(midiService.customPatches) { patch in
                    PresetButton(name: patch.name, program: patch.programNumber) {
                        midiPatchText = "\($0)"
                    }
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text(midiService.nordStageMode ? "Nord Stage Patches" : "Custom Patches")
        }
    }

    private var presetsSection: some View {
        Section {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 10) {
                PresetButton(name: "Piano", program: 0) { midiPatchText = "\($0)" }
                PresetButton(name: "E.Piano", program: 4) { midiPatchText = "\($0)" }
                PresetButton(name: "Organ", program: 16) { midiPatchText = "\($0)" }
                PresetButton(name: "Accordion", program: 21) { midiPatchText = "\($0)" }
                PresetButton(name: "Nylon Gtr", program: 24) { midiPatchText = "\($0)" }
                PresetButton(name: "Steel Gtr", program: 25) { midiPatchText = "\($0)" }
                PresetButton(name: "Clean Gtr", program: 27) { midiPatchText = "\($0)" }
                PresetButton(name: "Distortion", program: 30) { midiPatchText = "\($0)" }
                PresetButton(name: "Bass", program: 33) { midiPatchText = "\($0)" }
                PresetButton(name: "Strings", program: 48) { midiPatchText = "\($0)" }
                PresetButton(name: "Synth Lead", program: 80) { midiPatchText = "\($0)" }
                PresetButton(name: "Synth Pad", program: 88) { midiPatchText = "\($0)" }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Quick Presets (GM Standard)")
        }
    }
    
    private var notesSection: some View {
        Section {
            TextEditor(text: $notes)
                .frame(minHeight: 100)
        } header: {
            Text("Notes")
        }
    }
    
    private var fileInfoSection: some View {
        Section {
            HStack {
                Text("File Name")
                Spacer()
                Text(song.fullFileName)
                    .foregroundColor(.secondary)
            }
            HStack {
                Text("File Type")
                Spacer()
                Text(song.isPDF ? "PDF Document" : "Word Document")
                    .foregroundColor(.secondary)
            }
            if let pageCount = song.pageCount {
                HStack {
                    Text("Pages")
                    Spacer()
                    Text("\(pageCount)")
                        .foregroundColor(.secondary)
                }
            }
            HStack {
                Text("Added")
                Spacer()
                Text(formatDate(song.dateAdded))
                    .foregroundColor(.secondary)
            }
        } header: {
            Text("File Information")
        }
    }
    
    // MARK: - Helper Methods
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func handleTapTempo() {
        let now = Date()

        // Reset if last tap was more than 2 seconds ago
        if let lastTap = tapTimes.last, now.timeIntervalSince(lastTap) > 2.0 {
            tapTimes.removeAll()
        }

        tapTimes.append(now)

        // Keep only the last 8 taps
        if tapTimes.count > 8 {
            tapTimes.removeFirst()
        }

        // Need at least 2 taps to calculate BPM
        guard tapTimes.count >= 2 else { return }

        // Calculate average interval between taps
        var totalInterval: TimeInterval = 0
        for i in 1..<tapTimes.count {
            totalInterval += tapTimes[i].timeIntervalSince(tapTimes[i - 1])
        }
        let averageInterval = totalInterval / Double(tapTimes.count - 1)

        // Convert to BPM
        let bpm = Int(round(60.0 / averageInterval))

        // Clamp to reasonable range
        if bpm >= 20 && bpm <= 300 {
            tempo = "\(bpm)"
        }
    }
    
    private func loadSongData() {
        title = song.title
        artist = song.artist ?? ""
        // Extract just the number from tempo (in case it has "BPM" suffix)
        if let existingTempo = song.tempo {
            let digits = existingTempo.filter { $0.isNumber }
            tempo = String(digits.prefix(3))
        } else {
            tempo = ""
        }
        key = song.key ?? ""
        notes = song.notes ?? ""
        
        midiEnabled = song.midiProgramNumber != nil
        midiChannelText = "\((song.midiChannel ?? 0) + 1)"
        midiPatchText = "\(song.midiProgramNumber ?? 0)"
        useBankSelect = song.midiBankMSB != nil || song.midiBankLSB != nil
        bankMSBText = "\(song.midiBankMSB ?? 0)"
        bankLSBText = "\(song.midiBankLSB ?? 0)"
    }
    
    private func saveChanges() {
        song.title = title
        song.artist = artist.isEmpty ? nil : artist
        song.tempo = tempo.isEmpty ? nil : tempo
        song.key = key.isEmpty ? nil : key
        song.notes = notes.isEmpty ? nil : notes
        song.lastModified = Date()
        
        if midiEnabled {
            if let channel = Int(midiChannelText) {
                song.midiChannel = max(0, min(15, channel - 1))
            } else {
                song.midiChannel = 0
            }
            
            if let patch = Int(midiPatchText) {
                song.midiProgramNumber = max(0, min(127, patch))
            } else {
                song.midiProgramNumber = 0
            }
            
            if useBankSelect {
                if let msb = Int(bankMSBText) {
                    song.midiBankMSB = max(0, min(127, msb))
                }
                if let lsb = Int(bankLSBText) {
                    song.midiBankLSB = max(0, min(127, lsb))
                }
            } else {
                song.midiBankMSB = nil
                song.midiBankLSB = nil
            }
        } else {
            song.midiChannel = nil
            song.midiProgramNumber = nil
            song.midiBankMSB = nil
            song.midiBankLSB = nil
        }

        documentService.saveSong(song)
        dismiss()
    }
    
    private func gmProgramName(_ program: Int) -> String {
        let names = [
            "Acoustic Grand Piano", "Bright Acoustic Piano", "Electric Grand Piano", "Honky-tonk Piano",
            "Electric Piano 1", "Electric Piano 2", "Harpsichord", "Clavinet",
            "Celesta", "Glockenspiel", "Music Box", "Vibraphone",
            "Marimba", "Xylophone", "Tubular Bells", "Dulcimer",
            "Drawbar Organ", "Percussive Organ", "Rock Organ", "Church Organ",
            "Reed Organ", "Accordion", "Harmonica", "Tango Accordion",
            "Acoustic Guitar (nylon)", "Acoustic Guitar (steel)", "Electric Guitar (jazz)", "Electric Guitar (clean)",
            "Electric Guitar (muted)", "Overdriven Guitar", "Distortion Guitar", "Guitar Harmonics",
            "Acoustic Bass", "Electric Bass (finger)", "Electric Bass (pick)", "Fretless Bass",
            "Slap Bass 1", "Slap Bass 2", "Synth Bass 1", "Synth Bass 2",
            "Violin", "Viola", "Cello", "Contrabass",
            "Tremolo Strings", "Pizzicato Strings", "Orchestral Harp", "Timpani",
            "String Ensemble 1", "String Ensemble 2", "Synth Strings 1", "Synth Strings 2",
            "Choir Aahs", "Voice Oohs", "Synth Choir", "Orchestra Hit",
            "Trumpet", "Trombone", "Tuba", "Muted Trumpet",
            "French Horn", "Brass Section", "Synth Brass 1", "Synth Brass 2",
            "Soprano Sax", "Alto Sax", "Tenor Sax", "Baritone Sax",
            "Oboe", "English Horn", "Bassoon", "Clarinet",
            "Piccolo", "Flute", "Recorder", "Pan Flute",
            "Blown Bottle", "Shakuhachi", "Whistle", "Ocarina",
            "Lead 1 (square)", "Lead 2 (sawtooth)", "Lead 3 (calliope)", "Lead 4 (chiff)",
            "Lead 5 (charang)", "Lead 6 (voice)", "Lead 7 (fifths)", "Lead 8 (bass + lead)",
            "Pad 1 (new age)", "Pad 2 (warm)", "Pad 3 (polysynth)", "Pad 4 (choir)",
            "Pad 5 (bowed)", "Pad 6 (metallic)", "Pad 7 (halo)", "Pad 8 (sweep)",
            "FX 1 (rain)", "FX 2 (soundtrack)", "FX 3 (crystal)", "FX 4 (atmosphere)",
            "FX 5 (brightness)", "FX 6 (goblins)", "FX 7 (echoes)", "FX 8 (sci-fi)",
            "Sitar", "Banjo", "Shamisen", "Koto",
            "Kalimba", "Bagpipe", "Fiddle", "Shanai",
            "Tinkle Bell", "Agogo", "Steel Drums", "Woodblock",
            "Taiko Drum", "Melodic Tom", "Synth Drum", "Reverse Cymbal",
            "Guitar Fret Noise", "Breath Noise", "Seashore", "Bird Tweet",
            "Telephone Ring", "Helicopter", "Applause", "Gunshot"
        ]
        guard program >= 0, program < names.count else { return "Unknown" }
        return "GM \(program): \(names[program])"
    }
}

struct PresetButton: View {
    let name: String
    let program: Int
    let action: (Int) -> Void
    
    var body: some View {
        Button {
            action(program)
        } label: {
            VStack(spacing: 2) {
                Text(name)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text("\(program)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}
