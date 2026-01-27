import SwiftUI
import CoreAudioKit

struct MIDISettingsView: View {
    @ObservedObject var midiService: MIDIService
    @ObservedObject var overridesService: LocalMIDIOverridesService
    @Environment(\.dismiss) var dismiss
    @State private var showingAddPatch = false
    @State private var editingPatch: MIDIPatch?
    @State private var showingBluetoothMIDI = false

    var body: some View {
        NavigationView {
            List {
                Section {
                    HStack {
                        Text("MIDI Status")
                        Spacer()
                        Text(midiService.isConnected ? "Connected" : "Not Connected")
                            .foregroundColor(midiService.isConnected ? .green : .secondary)
                    }
                    if let dest = midiService.connectedDestination {
                        HStack {
                            Text("Connected to")
                            Spacer()
                            Text(dest.name)
                                .foregroundColor(.green)
                        }
                    }
                } header: { Text("Status") }
                footer: {
                    Text("Connect to a synthesizer, keyboard, or workstation to send program changes when songs change.")
                }
                
                Section {
                    Toggle("Nord Stage Mode", isOn: $midiService.nordStageMode)
                } header: {
                    Text("Instrument Settings")
                } footer: {
                    Text("Enable for Nord Stage 2/3 keyboards. Automatically sends Bank MSB=0, LSB=3 before each program change.")
                }

                Section {
                    Picker("Active Instrument", selection: $overridesService.activeInstrumentType) {
                        ForEach(MIDIInstrumentType.allCases) { type in
                            Label(type.displayName, systemImage: type.iconName)
                                .tag(type)
                        }
                    }

                    Toggle("Use Local Overrides", isOn: $overridesService.useLocalOverrides)
                } header: {
                    Text("Multi-Instrument Settings")
                } footer: {
                    Text("Select which instrument's MIDI profile to use. Local overrides are device-specific settings that don't sync to cloud.")
                }

                Section {
                    ForEach(midiService.customPatches) { patch in
                        Button {
                            editingPatch = patch
                        } label: {
                            HStack {
                                Text(patch.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text("PC \(patch.programNumber)")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                    }
                    .onDelete { indexSet in
                        for index in indexSet {
                            midiService.deletePatch(midiService.customPatches[index])
                        }
                    }
                    .onMove { source, destination in
                        midiService.movePatch(from: source, to: destination)
                    }

                    Button {
                        showingAddPatch = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                            Text("Add Custom Patch")
                        }
                    }

                    Button {
                        midiService.resetPatchesToDefaults()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundColor(.orange)
                            Text("Reset to Nord Defaults")
                        }
                    }
                } header: {
                    HStack {
                        Text("Custom Patches")
                        Spacer()
                        EditButton()
                            .font(.caption)
                    }
                } footer: {
                    Text("Define your instrument's patches here. These appear as quick presets when editing songs.")
                }

                Section {
                    Button {
                        showingBluetoothMIDI = true
                    } label: {
                        HStack {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .foregroundColor(.blue)
                            Text("Connect Bluetooth MIDI Device")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Bluetooth MIDI")
                } footer: {
                    Text("Pair with wireless MIDI controllers, foot pedals, and instruments.")
                }

                Section("MIDI Destinations (Instruments)") {
                    if midiService.availableDestinations.isEmpty {
                        Text("No MIDI devices found")
                            .foregroundColor(.secondary)
                            .font(.subheadline)
                        Text("Connect a keyboard, synth, or workstation via USB or Bluetooth")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    } else {
                        ForEach(midiService.availableDestinations) { destination in
                            HStack {
                                Image(systemName: "pianokeys.fill")
                                    .foregroundColor(midiService.connectedDestination == destination ? .green : .blue)
                                Text(destination.name)
                                Spacer()
                                if midiService.connectedDestination == destination {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                } else {
                                    Button("Connect") {
                                        midiService.connectToDestination(destination)
                                    }
                                    .font(.caption)
                                    .buttonStyle(.bordered)
                                }
                            }
                        }
                    }
                }
                
                Section("How It Works") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Program Changes")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Text("Each song can be assigned a MIDI program change message. When you advance to that song, ZahlStand sends the program change to your connected instrument to switch patches automatically.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("Setup Steps:")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .padding(.top, 8)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("1. Connect your keyboard/synth via USB or Bluetooth")
                            Text("2. Select it in the list above")
                            Text("3. Edit songs to assign MIDI program numbers")
                            Text("4. When you swipe to a song, the patch changes!")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                
                if midiService.isConnected {
                    Section {
                        Button(role: .destructive) {
                            midiService.disconnect()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Disconnect")
                                Spacer()
                            }
                        }
                    }
                }
                
                Section {
                    Button {
                        midiService.scanDevices()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh Devices")
                        }
                    }
                }
            }
            .navigationTitle("MIDI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingAddPatch) {
                PatchEditorView(midiService: midiService, patch: nil)
            }
            .sheet(item: $editingPatch) { patch in
                PatchEditorView(midiService: midiService, patch: patch)
            }
            .sheet(isPresented: $showingBluetoothMIDI, onDismiss: {
                // Refresh device list after Bluetooth configuration
                midiService.scanDevices()
            }) {
                BluetoothMIDIView()
            }
        }
    }
}

// MARK: - Patch Editor View

struct PatchEditorView: View {
    @ObservedObject var midiService: MIDIService
    let patch: MIDIPatch?
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var programNumber: String = ""

    var isEditing: Bool { patch != nil }

    var body: some View {
        NavigationView {
            Form {
                Section {
                    TextField("Patch Name", text: $name)
                        .autocapitalization(.words)

                    HStack {
                        Text("Program Number")
                        Spacer()
                        TextField("0-127", text: $programNumber)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 60)
                    }
                } footer: {
                    Text("Program number is 0-127 (MIDI standard)")
                }

                if isEditing {
                    Section {
                        Button(role: .destructive) {
                            if let patch = patch {
                                midiService.deletePatch(patch)
                            }
                            dismiss()
                        } label: {
                            HStack {
                                Spacer()
                                Text("Delete Patch")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Patch" : "Add Patch")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePatch()
                    }
                    .disabled(name.isEmpty || programNumber.isEmpty)
                }
            }
            .onAppear {
                if let patch = patch {
                    name = patch.name
                    programNumber = "\(patch.programNumber)"
                }
            }
        }
    }

    private func savePatch() {
        guard let program = Int(programNumber), program >= 0, program <= 127 else { return }

        if let existingPatch = patch {
            var updated = existingPatch
            updated.name = name
            updated.programNumber = program
            midiService.updatePatch(updated)
        } else {
            let newPatch = MIDIPatch(name: name, programNumber: program)
            midiService.addPatch(newPatch)
        }
        dismiss()
    }
}

// MARK: - Bluetooth MIDI Configuration

struct BluetoothMIDIView: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UINavigationController {
        let btMidiVC = CABTMIDICentralViewController()
        let navController = UINavigationController(rootViewController: btMidiVC)
        btMidiVC.navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done,
            target: context.coordinator,
            action: #selector(Coordinator.dismissView)
        )
        return navController
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject {
        let parent: BluetoothMIDIView

        init(_ parent: BluetoothMIDIView) {
            self.parent = parent
        }

        @objc func dismissView() {
            parent.dismiss()
        }
    }
}
