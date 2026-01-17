import SwiftUI

struct MIDISettingsView: View {
    @ObservedObject var midiService: MIDIService
    @Environment(\.dismiss) var dismiss
    
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
        }
    }
}
