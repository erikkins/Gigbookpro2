import SwiftUI

@main
struct ZahlStandApp: App {
    @StateObject private var documentService = DocumentService()
    @StateObject private var songlistService = SonglistService()
    @StateObject private var midiService = MIDIService()
    @StateObject private var azureService: AzureStorageService
    @StateObject private var peerService = PeerConnectivityService()
    
    init() {
        _azureService = StateObject(wrappedValue: AzureStorageService(
            accountName: AppConfig.azureAccountName,
            accountKey: AppConfig.azureAccountKey,
            containerName: "songlists"
        ))
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(documentService)
                .environmentObject(songlistService)
                .environmentObject(midiService)
                .environmentObject(azureService)
                .environmentObject(peerService)
                .onAppear {
                    songlistService.documentService = documentService
                    songlistService.loadSonglists()
                    
                    Task { try? await azureService.createContainerIfNeeded() }
                    documentService.copyBundledSongsIfNeeded()
                }
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var documentService: DocumentService
    @EnvironmentObject var songlistService: SonglistService
    @EnvironmentObject var midiService: MIDIService
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var body: some View {
        if horizontalSizeClass == .compact {
            // iPhone: Stack navigation
            NavigationView {
                SidebarView()
            }
            .navigationViewStyle(.stack)
        } else {
            // iPad: Column navigation
            NavigationView {
                SidebarView()
                DocumentViewer(
                    documentService: documentService,
                    songlistService: songlistService,
                    midiService: midiService
                )
            }
            .navigationViewStyle(.columns)
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject var documentService: DocumentService
    @EnvironmentObject var songlistService: SonglistService
    @EnvironmentObject var midiService: MIDIService
    @State private var selectedTab = 0
    @State private var showingNewSonglist = false
    @State private var showingCloudSync = false
    @State private var showingFileImporter = false
    
    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $selectedTab) {
                Text("Songs").tag(0)
                Text("Songlists").tag(1)
            }.pickerStyle(.segmented).padding()
            
            if selectedTab == 0 { SongLibraryView() } else { SonglistLibraryView() }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if selectedTab == 0 {
                    Button { showingFileImporter = true } label: {
                        Label("Import Files", systemImage: "plus.circle.fill")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    if selectedTab == 1 {
                        Button { showingNewSonglist = true } label: {
                            Label("New Songlist", systemImage: "plus")
                        }
                    }
                    Button { showingCloudSync = true } label: {
                        Label("Cloud Sync", systemImage: "icloud")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .fileImporter(
            isPresented: $showingFileImporter,
            allowedContentTypes: [.pdf, .commaSeparatedText],
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showingNewSonglist) { NewSonglistView() }
        .sheet(isPresented: $showingCloudSync) { CloudSyncView() }
        .navigationTitle(selectedTab == 0 ? "Songs" : "Songlists")
    }
    
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                documentService.importDocument(from: url) { importResult in
                    if case .success(let song) = importResult {
                        print("✅ Imported: \(song.title)")
                    }
                }
            }
        case .failure: break
        }
    }
}

// MARK: - Song Library View

struct SongLibraryView: View {
    @EnvironmentObject var documentService: DocumentService
    @EnvironmentObject var songlistService: SonglistService
    @EnvironmentObject var midiService: MIDIService
    @State private var searchText = ""
    @State private var songToEdit: Song?
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var filteredSongs: [Song] {
        searchText.isEmpty ? documentService.songs : documentService.searchSongs(query: searchText)
    }
    
    var body: some View {
        List {
            ForEach(filteredSongs) { song in
                SongLibraryRow(song: song, onEdit: { songToEdit = song })
            }
        }
        .searchable(text: $searchText, prompt: "Search songs")
        .overlay {
            if documentService.songs.isEmpty { EmptyLibraryView() }
        }
        .sheet(item: $songToEdit) { song in
            SongEditorView(song: song)
                .environmentObject(documentService)
        }
    }
}

struct SongLibraryRow: View {
    @ObservedObject var song: Song
    @EnvironmentObject var documentService: DocumentService
    @EnvironmentObject var songlistService: SonglistService
    @EnvironmentObject var midiService: MIDIService
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    let onEdit: () -> Void
    
    var body: some View {
        HStack {
            if horizontalSizeClass == .compact {
                // iPhone: NavigationLink
                NavigationLink {
                    DocumentViewer(
                        documentService: documentService,
                        songlistService: songlistService,
                        midiService: midiService,
                        initialSong: song
                    )
                } label: {
                    songContent
                }
            } else {
                // iPad: Tap to view in detail pane
                songContent
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NotificationCenter.default.post(name: .viewSingleSong, object: song)
                    }
            }
            
            Spacer()
            
            Button { onEdit() } label: {
                Image(systemName: "pencil.circle")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
        .contextMenu {
            if !songlistService.songlists.isEmpty {
                Menu {
                    ForEach(songlistService.songlists) { songlist in
                        Button {
                            songlist.addSong(song)
                            try? songlistService.saveSonglist(songlist)
                        } label: {
                            Label(songlist.name, systemImage: "music.note.list")
                        }
                    }
                } label: {
                    Label("Add to Songlist", systemImage: "plus.rectangle.on.rectangle")
                }
            }
            
            Divider()
            
            Button(role: .destructive) {
                try? documentService.deleteSong(song)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private var songContent: some View {
        HStack {
            Image(systemName: song.isPDF ? "doc.fill" : "doc.text.fill")
                .foregroundColor(song.isPDF ? .red : .blue)
                .font(.title3)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(song.title).font(.headline)
                if let artist = song.artist {
                    Text(artist).font(.caption).foregroundColor(.secondary)
                }
                if let midiDesc = song.midiProgramDescription {
                    HStack(spacing: 4) {
                        Image(systemName: "pianokeys").font(.caption2)
                        Text(midiDesc).font(.caption2)
                    }
                    .foregroundColor(.orange)
                }
            }
        }
    }
}

// MARK: - Songlist Library View

struct SonglistLibraryView: View {
    @EnvironmentObject var songlistService: SonglistService
    @EnvironmentObject var documentService: DocumentService
    @EnvironmentObject var midiService: MIDIService
    @State private var selectedSonglist: Songlist?
    
    var body: some View {
        List {
            ForEach(songlistService.songlists) { songlist in
                SonglistLibraryRow(
                    songlist: songlist,
                    onEdit: { selectedSonglist = songlist },
                    onClone: { cloneSonglist(songlist) }
                )
            }
            .onDelete(perform: deleteSonglists)
        }
        .overlay {
            if songlistService.songlists.isEmpty { EmptySonglistsView() }
        }
        .fullScreenCover(item: $selectedSonglist) { songlist in
            SonglistEditorView(songlist: songlist)
                .environmentObject(songlistService)
                .environmentObject(documentService)
        }
    }
    
    private func cloneSonglist(_ original: Songlist) {
        let clone = Songlist(name: "\(original.name) (Copy)", songIds: original.songIds)
        clone.event = original.event
        clone.venue = original.venue
        clone.eventDate = original.eventDate
        clone.notes = original.notes
        clone.documentService = documentService
        
        try? songlistService.saveSonglist(clone)
        songlistService.loadSonglists()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            selectedSonglist = clone
        }
    }
    
    private func deleteSonglists(at offsets: IndexSet) {
        for index in offsets {
            try? songlistService.deleteSonglist(songlistService.songlists[index])
        }
    }
}

struct SonglistLibraryRow: View {
    @ObservedObject var songlist: Songlist
    @EnvironmentObject var songlistService: SonglistService
    @EnvironmentObject var documentService: DocumentService
    @EnvironmentObject var midiService: MIDIService
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    let onEdit: () -> Void
    let onClone: () -> Void
    
    var body: some View {
        HStack {
            if horizontalSizeClass == .compact {
                // iPhone: NavigationLink
                NavigationLink {
                    DocumentViewer(
                        documentService: documentService,
                        songlistService: songlistService,
                        midiService: midiService,
                        initialSonglist: songlist
                    )
                } label: {
                    songlistContent
                }
            } else {
                // iPad: Tap to activate
                songlistContent
                    .contentShape(Rectangle())
                    .onTapGesture {
                        songlistService.setActiveSonglist(songlist)
                    }
            }
            
            Spacer()
            
            Button { onEdit() } label: {
                Image(systemName: "pencil.circle")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button { onClone() } label: {
                Label("Clone Songlist", systemImage: "doc.on.doc")
            }
            
            Divider()
            
            Button(role: .destructive) {
                try? songlistService.deleteSonglist(songlist)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
    
    private var songlistContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(songlist.name).font(.headline)
            Text("\(songlist.songCount) songs").font(.caption).foregroundColor(.secondary)
            if let event = songlist.event {
                Text(event).font(.caption2).foregroundColor(.secondary).italic()
            }
        }
    }
}

// MARK: - Empty Views

struct EmptyLibraryView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "music.note").font(.system(size: 60)).foregroundColor(.secondary)
            Text("No Songs Yet").font(.title3).fontWeight(.semibold)
            Text("Tap the + button to import PDF or Word documents")
                .foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
        }.padding()
    }
}

struct EmptySonglistsView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "list.bullet").font(.system(size: 60)).foregroundColor(.secondary)
            Text("No Songlists Yet").font(.title3).fontWeight(.semibold)
            Text("Create a songlist to organize your music")
                .foregroundColor(.secondary).multilineTextAlignment(.center).padding(.horizontal)
        }.padding()
    }
}

// MARK: - Notification for viewing single song

extension Notification.Name {
    static let viewSingleSong = Notification.Name("viewSingleSong")
}
