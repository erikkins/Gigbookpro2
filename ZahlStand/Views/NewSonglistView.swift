import SwiftUI

struct NewSonglistView: View {
    @EnvironmentObject var songlistService: SonglistService
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var event = ""
    @State private var venue = ""
    @State private var eventDate = Date()
    @State private var notes = ""
    @State private var includeDate = false
    
    var body: some View {
        NavigationView {
            Form {
                Section("Songlist Details") {
                    TextField("Songlist Name", text: $name).textInputAutocapitalization(.words)
                    TextField("Event Name (Optional)", text: $event).textInputAutocapitalization(.words)
                    TextField("Venue (Optional)", text: $venue).textInputAutocapitalization(.words)
                }
                Section("Event Date") {
                    Toggle("Include Event Date", isOn: $includeDate)
                    if includeDate {
                        DatePicker("Date", selection: $eventDate, displayedComponents: [.date])
                    }
                }
                Section("Notes") {
                    TextEditor(text: $notes).frame(minHeight: 100)
                }
            }
            .navigationTitle("New Songlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createSonglist() }.disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func createSonglist() {
        let songlist = Songlist(
            name: name, songIds: [],
            event: event.isEmpty ? nil : event,
            venue: venue.isEmpty ? nil : venue,
            eventDate: includeDate ? eventDate : nil
        )
        songlist.notes = notes.isEmpty ? nil : notes
        try? songlistService.saveSonglist(songlist)
        dismiss()
    }
}
