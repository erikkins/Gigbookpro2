import SwiftUI

struct SonglistEditorView: View {
    @ObservedObject var songlist: Songlist
    @EnvironmentObject var songlistService: SonglistService
    @EnvironmentObject var documentService: DocumentService
    @Environment(\.dismiss) var dismiss
    
    @State private var name: String = ""
    @State private var event: String = ""
    @State private var venue: String = ""
    @State private var eventDate: Date = Date()
    @State private var includeDate: Bool = false
    
    // Working copy of included song IDs
    @State private var includedSongIds: [String] = []
    @State private var searchText: String = ""
    
    var includedSongs: [Song] {
        includedSongIds.compactMap { id in
            documentService.songs.first { $0.id == id }
        }
    }
    
    var availableSongs: [Song] {
        let notIncluded = documentService.songs.filter { song in
            !includedSongIds.contains(song.id)
        }
        if searchText.isEmpty {
            return notIncluded
        }
        return notIncluded.filter { 
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.artist?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Compact header bar
                headerBar
                
                Divider()
                
                // Two-column layout
                HStack(spacing: 0) {
                    // Left: Available Songs
                    availableSongsColumn
                        .frame(width: geometry.size.width / 2)
                    
                    Divider()
                    
                    // Right: Included Songs
                    includedSongsColumn
                        .frame(width: geometry.size.width / 2)
                }
            }
        }
        .edgesIgnoringSafeArea(.bottom)
        .onAppear { loadSonglistData() }
    }
    
    // MARK: - Header Bar
    
    private var headerBar: some View {
        HStack(spacing: 16) {
            Button("Cancel") { dismiss() }
                .foregroundColor(.red)
            
            Divider().frame(height: 30)
            
            HStack(spacing: 8) {
                Text("Name:")
                    .foregroundColor(.secondary)
                TextField("Songlist Name", text: $name)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: 200)
            }
            
            HStack(spacing: 8) {
                Text("Event:")
                    .foregroundColor(.secondary)
                TextField("Optional", text: $event)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: 150)
            }
            
            HStack(spacing: 8) {
                Text("Venue:")
                    .foregroundColor(.secondary)
                TextField("Optional", text: $venue)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .frame(maxWidth: 150)
            }
            
            Spacer()
            
            Text("\(includedSongIds.count) songs")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Divider().frame(height: 30)
            
            Button("Save") { saveChanges() }
                .disabled(name.isEmpty)
                .font(.headline)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(UIColor.systemGroupedBackground))
    }
    
    // MARK: - Available Songs Column (Left)
    
    private var availableSongsColumn: some View {
        VStack(spacing: 0) {
            // Column header with search
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "music.note.list")
                    Text("Available Songs")
                        .font(.headline)
                    Spacer()
                    Text("\(availableSongs.count)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(10)
                }
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search songs...", text: $searchText)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(UIColor.systemBackground))
                .cornerRadius(8)
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            
            // Song list
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(availableSongs) { song in
                        AvailableSongRow(song: song) {
                            addSong(song)
                        }
                        .onDrag {
                            return NSItemProvider(object: song.id as NSString)
                        }
                    }
                }
            }
            .background(Color(UIColor.systemBackground))
        }
    }
    
    // MARK: - Included Songs Column (Right)
    
    private var includedSongsColumn: some View {
        VStack(spacing: 0) {
            // Column header
            HStack {
                Image(systemName: "list.number")
                Text("Songlist Order")
                    .font(.headline)
                Spacer()
                Text("\(includedSongIds.count)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.2))
                    .cornerRadius(10)
                
                if !includedSongIds.isEmpty {
                    Button {
                        withAnimation {
                            includedSongIds.removeAll()
                        }
                    } label: {
                        Text("Clear All")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                    .padding(.leading, 8)
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            
            // Included songs list
            if includedSongs.isEmpty {
                emptyDropZone
            } else {
                List {
                    ForEach(Array(includedSongs.enumerated()), id: \.element.id) { index, song in
                        IncludedSongRow(song: song, index: index + 1)
                    }
                    .onMove(perform: moveSongs)
                    .onDelete(perform: deleteSongs)
                }
                .listStyle(PlainListStyle())
                .environment(\.editMode, .constant(.active))
            }
        }
        .onDrop(of: [.text], isTargeted: nil) { providers in
            handleDrop(providers: providers)
        }
    }
    
    private var emptyDropZone: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "arrow.left.circle")
                .font(.system(size: 50))
                .foregroundColor(.secondary)
            Text("Add songs from the left")
                .font(.title3)
                .foregroundColor(.secondary)
            Text("Tap + or drag songs here")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
    
    // MARK: - Actions
    
    private func addSong(_ song: Song) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if !includedSongIds.contains(song.id) {
                includedSongIds.append(song.id)
            }
        }
    }
    
    private func moveSongs(from source: IndexSet, to destination: Int) {
        includedSongIds.move(fromOffsets: source, toOffset: destination)
    }
    
    private func deleteSongs(at offsets: IndexSet) {
        includedSongIds.remove(atOffsets: offsets)
    }
    
    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        
        provider.loadObject(ofClass: NSString.self) { (item, error) in
            if let songId = item as? String {
                DispatchQueue.main.async {
                    if !includedSongIds.contains(songId) {
                        withAnimation {
                            includedSongIds.append(songId)
                        }
                    }
                }
            }
        }
        return true
    }
    
    // MARK: - Load/Save
    
    private func loadSonglistData() {
        name = songlist.name
        event = songlist.event ?? ""
        venue = songlist.venue ?? ""
        includeDate = songlist.eventDate != nil
        eventDate = songlist.eventDate ?? Date()
        includedSongIds = songlist.songIds
    }
    
    private func saveChanges() {
        songlist.name = name
        songlist.event = event.isEmpty ? nil : event
        songlist.venue = venue.isEmpty ? nil : venue
        songlist.eventDate = includeDate ? eventDate : nil
        songlist.dateModified = Date()
        songlist.songIds = includedSongIds
        
        try? songlistService.saveSonglist(songlist)
        dismiss()
    }
}

// MARK: - Row Views

struct AvailableSongRow: View {
    let song: Song
    let onAdd: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Add button - tapping adds immediately
            Button {
                onAdd()
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundColor(.green)
            }
            .buttonStyle(PlainButtonStyle())
            
            Image(systemName: song.isPDF ? "doc.fill" : "doc.text.fill")
                .foregroundColor(song.isPDF ? .red : .blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.subheadline)
                    .lineLimit(1)
                if let artist = song.artist {
                    Text(artist)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            if song.hasMIDIProgramChange {
                HStack(spacing: 4) {
                    Image(systemName: "pianokeys")
                    Text(song.midiProgramDescription ?? "")
                }
                .font(.caption2)
                .foregroundColor(.orange)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(UIColor.systemBackground))
        .contentShape(Rectangle())
    }
}

struct IncludedSongRow: View {
    let song: Song
    let index: Int
    
    var body: some View {
        HStack(spacing: 12) {
            Text("\(index)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Color.blue)
                .cornerRadius(8)
            
            Image(systemName: song.isPDF ? "doc.fill" : "doc.text.fill")
                .foregroundColor(song.isPDF ? .red : .blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(song.title)
                    .font(.subheadline)
                    .lineLimit(1)
                if song.hasMIDIProgramChange {
                    Text(song.midiProgramDescription ?? "")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
        }
        .contentShape(Rectangle())
    }
}
