import SwiftUI
import UIKit
import WebKit

@main
struct ZahlStandApp: App {
    @StateObject private var documentService = DocumentService()
    @StateObject private var songlistService = SonglistService()
    @StateObject private var midiService = MIDIService()
    @StateObject private var azureService: AzureStorageService
    @StateObject private var peerService = PeerConnectivityService()
    @StateObject private var overridesService = LocalMIDIOverridesService()
    @StateObject private var annotationService = AnnotationService()
    
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
                .environmentObject(overridesService)
                .environmentObject(annotationService)
                .onAppear {
                    // Prevent screen from dimming during performances
                    UIApplication.shared.isIdleTimerDisabled = true

                    songlistService.documentService = documentService
                    songlistService.loadSonglists()

                    // Wire up MIDI service to use local overrides
                    midiService.overridesService = overridesService

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
    @EnvironmentObject var overridesService: LocalMIDIOverridesService
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @State private var importedSongToEdit: Song?
    @State private var showMigrationError = false

    var body: some View {
        ZStack {
            Group {
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
            .onOpenURL { url in
                handleIncomingFile(url: url)
            }
            .sheet(item: $importedSongToEdit) { song in
                SongEditorView(song: song)
                    .environmentObject(documentService)
                    .environmentObject(midiService)
                    .environmentObject(overridesService)
            }

            // Migration overlay
            if documentService.isMigrating {
                MigrationOverlayView(
                    progress: documentService.migrationProgress,
                    status: documentService.migrationStatus
                )
            }
        }
        .onAppear {
            // Check and run migration if needed
            if documentService.needsWordFileMigration() {
                Task {
                    await documentService.migrateWordFilesToPDF()
                    if documentService.migrationError != nil {
                        showMigrationError = true
                    }
                }
            }
        }
        .alert("Migration Error", isPresented: $showMigrationError) {
            Button("OK", role: .cancel) {
                documentService.migrationError = nil
            }
        } message: {
            Text(documentService.migrationError ?? "Some files could not be converted.")
        }
    }

    private func handleIncomingFile(url: URL) {
        // For AirDrop files, we need to copy from the inbox to our documents
        documentService.importDocument(from: url) { result in
            switch result {
            case .success(let song):
                // Open the song editor immediately
                importedSongToEdit = song
            case .failure(let error):
                print("Failed to import AirDrop file: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Migration Overlay

struct MigrationOverlayView: View {
    let progress: Double
    let status: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.7)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                Text("Migrating Documents")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("Converting Word documents to PDF for better performance...")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .frame(width: 250)
                    .tint(.blue)

                Text(status)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)

                Text("\(Int(progress * 100))%")
                    .font(.headline.monospacedDigit())
                    .foregroundColor(.white)
            }
            .padding(32)
            .background(Color(UIColor.systemGray5))
            .cornerRadius(16)
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
    @EnvironmentObject var overridesService: LocalMIDIOverridesService
    @State private var searchText = ""
    @State private var songToEdit: Song?
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    
    var filteredSongs: [Song] {
        searchText.isEmpty ? documentService.songs : documentService.searchSongs(query: searchText)
    }
    
    var body: some View {
        List {
            ForEach(filteredSongs) { song in
                SongLibraryRow(song: song, allSongs: filteredSongs, onEdit: { songToEdit = song })
            }
        }
        .searchable(text: $searchText, prompt: "Search songs")
        .overlay {
            if documentService.songs.isEmpty { EmptyLibraryView() }
        }
        .sheet(item: $songToEdit) { song in
            SongEditorView(song: song)
                .environmentObject(documentService)
                .environmentObject(midiService)
                .environmentObject(overridesService)
        }
    }
}

struct SongLibraryRow: View {
    @ObservedObject var song: Song
    let allSongs: [Song]
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
                        initialSong: song,
                        initialLibrarySongs: allSongs
                    )
                } label: {
                    songContent
                }
            } else {
                // iPad: Tap to view in detail pane
                songContent
                    .contentShape(Rectangle())
                    .onTapGesture {
                        NotificationCenter.default.post(
                            name: .viewSongFromLibrary,
                            object: nil,
                            userInfo: ["song": song, "allSongs": allSongs]
                        )
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
    @State private var showingShareSheet = false
    @State private var forScoreFileURL: URL?
    @State private var isExporting = false
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

            Button {
                Task { await exportToForScore() }
            } label: {
                Label(isExporting ? "Exporting..." : "Export to forScore", systemImage: "square.and.arrow.up")
            }
            .disabled(isExporting)

            Divider()

            Button(role: .destructive) {
                try? songlistService.deleteSonglist(songlist)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            if let url = forScoreFileURL {
                ShareSheet(items: [url])
            }
        }
        .fullScreenCover(isPresented: $isExporting) {
            ZStack {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Exporting to forScore...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(24)
                .background(Color(UIColor.systemGray5))
                .cornerRadius(12)
            }
            .background(ClearBackgroundView())
        }
    }

    private func exportToForScore() async {
        isExporting = true
        defer { isExporting = false }

        // Build forScore 4SS XML format with embedded PDF data
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\" ?>\n"
        xml += "<forScore kind=\"setlist\" version=\"1.0\" title=\"\(escapeXML(songlist.name))\">\n"

        for song in songlist.songs {
            let title = escapeXML(song.title)
            let pdfFileName = escapeXML(song.fullFileName)

            if let filePath = song.filePath, let pdfData = try? Data(contentsOf: filePath) {
                let base64 = pdfData.base64EncodedString()
                xml += "  <score title=\"\(title)\" path=\"\(pdfFileName)\" data=\"\(base64)\" />\n"
            } else {
                xml += "  <placeholder title=\"\(title)\" />\n"
            }
        }

        xml += "</forScore>\n"

        // Write to temp file
        let fileName = "\(songlist.name).4ss"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        do {
            try xml.write(to: tempURL, atomically: true, encoding: .utf8)
            forScoreFileURL = tempURL
            showingShareSheet = true
        } catch {
            print("Failed to export forScore file: \(error)")
        }
    }

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
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

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Clear Background for FullScreenCover

struct ClearBackgroundView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            view.superview?.superview?.backgroundColor = .clear
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Word to PDF Converter

@MainActor
class WordToPDFConverter: NSObject, WKNavigationDelegate {
    static let shared = WordToPDFConverter()

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Data?, Never>?

    func convert(url: URL) async -> Data? {
        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 612, height: 792)) // Letter size
            webView.navigationDelegate = self
            self.webView = webView

            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            // Wait a moment for rendering to complete
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

            let config = WKPDFConfiguration()
            config.rect = CGRect(x: 0, y: 0, width: 612, height: 792) // Letter size in points

            do {
                let pdfData = try await webView.pdf(configuration: config)
                self.continuation?.resume(returning: pdfData)
            } catch {
                print("Failed to create PDF: \(error)")
                self.continuation?.resume(returning: nil)
            }

            self.webView = nil
            self.continuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            print("WebView failed to load: \(error)")
            self.continuation?.resume(returning: nil)
            self.webView = nil
            self.continuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            print("WebView failed provisional navigation: \(error)")
            self.continuation?.resume(returning: nil)
            self.webView = nil
            self.continuation = nil
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let viewSingleSong = Notification.Name("viewSingleSong")
    static let viewSongFromLibrary = Notification.Name("viewSongFromLibrary")
}
