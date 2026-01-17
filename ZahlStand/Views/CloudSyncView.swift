import SwiftUI

struct CloudSyncView: View {
    @EnvironmentObject var azureService: AzureStorageService
    @EnvironmentObject var songlistService: SonglistService
    @EnvironmentObject var documentService: DocumentService
    @Environment(\.dismiss) var dismiss
    
    @State private var selectedTab = 0
    @State private var isLoadingLegacy = false
    @State private var isLoadingNew = false
    @State private var selectedLegacyBlob: String?
    @State private var legacyPreview: LegacySonglist?
    @State private var isMigrating = false
    @State private var migrationStatus: String = ""
    @State private var errorMessage: String?
    
    // Duplicate handling
    @State private var showDuplicateAlert = false
    @State private var duplicateSonglistName: String = ""
    @State private var pendingImportAction: (() async -> Void)?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                Picker("View", selection: $selectedTab) {
                    Text("Legacy (Old)").tag(0)
                    Text("New Format").tag(1)
                    Text("Upload").tag(2)
                }
                .pickerStyle(.segmented)
                .padding()
                
                switch selectedTab {
                case 0: legacyBlobsView
                case 1: newBlobsView
                case 2: uploadView
                default: EmptyView()
                }
            }
            .navigationTitle("Cloud Sync")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Error", isPresented: .constant(errorMessage != nil && !errorMessage!.starts(with: "✅"))) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Success", isPresented: .constant(errorMessage?.starts(with: "✅") == true)) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .alert("Songlist Already Exists", isPresented: $showDuplicateAlert) {
                Button("Replace", role: .destructive) {
                    if let action = pendingImportAction {
                        Task { await action() }
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingImportAction = nil
                }
            } message: {
                Text("'\(duplicateSonglistName)' already exists locally. Do you want to replace it?")
            }
        }
    }
    
    // MARK: - Helper to display blob name without .json
    
    private func displayName(for blob: String) -> String {
        if blob.lowercased().hasSuffix(".json") {
            return String(blob.dropLast(5))
        }
        return blob
    }
    
    // MARK: - Check for duplicate songlist
    
    private func songlistExists(_ name: String) -> Bool {
        songlistService.songlists.contains { $0.name.lowercased() == name.lowercased() }
    }
    
    private func deleteExistingSonglist(_ name: String) {
        if let existing = songlistService.songlists.first(where: { $0.name.lowercased() == name.lowercased() }) {
            try? songlistService.deleteSonglist(existing)
        }
    }
    
    // MARK: - Legacy Blobs View
    
    private var legacyBlobsView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Legacy Songlists (playlists)")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await loadLegacyBlobs() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoadingLegacy)
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            
            if isLoadingLegacy {
                ProgressView("Loading legacy songlists...")
                    .padding()
                Spacer()
            } else if azureService.legacyBlobs.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "cloud")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No Legacy Songlists")
                        .font(.title3)
                    Text("Tap Refresh to load from Azure")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                GeometryReader { geo in
                    HStack(spacing: 0) {
                        List(azureService.legacyBlobs, id: \.self, selection: $selectedLegacyBlob) { blob in
                            HStack {
                                Image(systemName: "doc.zipper")
                                    .foregroundColor(.orange)
                                Text(blob)
                                Spacer()
                                if selectedLegacyBlob == blob {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedLegacyBlob = blob
                                Task { await previewLegacyBlob(blob) }
                            }
                        }
                        .frame(width: geo.size.width * 0.4)
                        
                        Divider()
                        
                        legacyPreviewPane
                            .frame(width: geo.size.width * 0.6)
                    }
                }
            }
        }
        .onAppear {
            Task { await loadLegacyBlobs() }
        }
    }
    
    private var legacyPreviewPane: some View {
        VStack {
            if let preview = legacyPreview {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(preview.name)
                                .font(.title2)
                                .fontWeight(.bold)
                            Text("\(preview.songs.count) songs")
                                .foregroundColor(.secondary)
                            
                            // Show if duplicate exists
                            if songlistExists(preview.name) {
                                Label("Already imported", systemImage: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        Spacer()
                        
                        Button {
                            Task { await checkAndMigrateLegacy() }
                        } label: {
                            if isMigrating {
                                ProgressView()
                            } else {
                                Label(songlistExists(preview.name) ? "Re-import" : "Import & Convert", 
                                      systemImage: "arrow.down.doc")
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isMigrating)
                    }
                    .padding()
                    
                    if !migrationStatus.isEmpty {
                        Text(migrationStatus)
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.horizontal)
                    }
                    
                    Divider()
                    
                    List {
                        ForEach(Array(preview.songs.enumerated()), id: \.offset) { index, song in
                            HStack {
                                Text("\(index + 1)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .frame(width: 30)
                                
                                Image(systemName: song.path.hasSuffix(".pdf") ? "doc.fill" : "doc.text.fill")
                                    .foregroundColor(song.path.hasSuffix(".pdf") ? .red : .blue)
                                
                                VStack(alignment: .leading) {
                                    Text(song.name)
                                        .font(.subheadline)
                                    Text(song.path)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                if let data = song.fileData {
                                    Text(formatBytes(data.count))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "arrow.left")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("Select a legacy songlist to preview")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - New Blobs View
    
    private var newBlobsView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Format Songlists (songlists-v2)")
                    .font(.headline)
                Spacer()
                Button {
                    Task { await loadNewBlobs() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isLoadingNew)
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            
            if isLoadingNew {
                ProgressView("Loading...")
                    .padding()
                Spacer()
            } else if azureService.availableBlobs.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "cloud")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No New Format Songlists")
                        .font(.title3)
                    Text("Import legacy songlists or upload local ones")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(azureService.availableBlobs, id: \.self) { blob in
                        let name = displayName(for: blob)
                        let alreadyExists = songlistExists(name)
                        
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(.green)
                            
                            VStack(alignment: .leading) {
                                Text(name)
                                    .font(.body)
                                if alreadyExists {
                                    Label("Already imported", systemImage: "checkmark.circle.fill")
                                        .font(.caption2)
                                        .foregroundColor(.green)
                                }
                            }
                            
                            Spacer()
                            
                            Button {
                                Task { await checkAndDownloadNewBlob(blob) }
                            } label: {
                                Label(alreadyExists ? "Re-download" : "Download", 
                                      systemImage: "arrow.down.circle")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .onAppear {
            Task { await loadNewBlobs() }
        }
    }
    
    // MARK: - Upload View
    
    private var uploadView: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Upload Local Songlists")
                    .font(.headline)
                Spacer()
            }
            .padding()
            .background(Color(UIColor.secondarySystemGroupedBackground))
            
            if songlistService.songlists.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "list.bullet")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("No Local Songlists")
                        .font(.title3)
                    Text("Create songlists first to upload")
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                List {
                    ForEach(songlistService.songlists) { songlist in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(songlist.name)
                                    .font(.headline)
                                Text("\(songlist.songCount) songs")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Button {
                                Task { await uploadSonglist(songlist) }
                            } label: {
                                if azureService.isUploading {
                                    ProgressView()
                                } else {
                                    Label("Upload", systemImage: "icloud.and.arrow.up")
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(azureService.isUploading)
                        }
                    }
                }
                
                Text("Uploads include all song files, MIDI settings, and metadata")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding()
            }
        }
    }
    
    // MARK: - Actions
    
    private func loadLegacyBlobs() async {
        isLoadingLegacy = true
        defer { isLoadingLegacy = false }
        
        do {
            try await azureService.listLegacyBlobs()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func loadNewBlobs() async {
        isLoadingNew = true
        defer { isLoadingNew = false }
        
        do {
            try await azureService.listNewBlobs()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func previewLegacyBlob(_ name: String) async {
        do {
            migrationStatus = "Downloading..."
            let data = try await azureService.downloadLegacyBlob(name: name)
            migrationStatus = "Parsing..."
            legacyPreview = try azureService.parseLegacyBlob(data)
            migrationStatus = ""
        } catch {
            errorMessage = "Failed to preview: \(error.localizedDescription)"
            legacyPreview = nil
            migrationStatus = ""
        }
    }
    
    private func checkAndMigrateLegacy() async {
        guard let preview = legacyPreview else { return }
        
        if songlistExists(preview.name) {
            duplicateSonglistName = preview.name
            pendingImportAction = {
                await self.performLegacyMigration(replacing: true)
            }
            showDuplicateAlert = true
        } else {
            await performLegacyMigration(replacing: false)
        }
    }
    
    private func performLegacyMigration(replacing: Bool) async {
        guard let preview = legacyPreview else { return }
        
        isMigrating = true
        migrationStatus = "Importing \(preview.songs.count) files..."
        defer { isMigrating = false }
        
        do {
            // Delete existing if replacing
            if replacing {
                deleteExistingSonglist(preview.name)
            }
            
            let songlist = try await azureService.convertAndImportLegacy(
                preview,
                documentService: documentService,
                songlistService: songlistService
            )
            
            migrationStatus = "Uploading to cloud..."
            try await azureService.uploadSonglist(songlist, documentService: documentService)
            migrationStatus = "✅ '\(songlist.name)' migrated with \(songlist.songCount) songs!"
            
            await loadNewBlobs()
        } catch {
            errorMessage = "Migration failed: \(error.localizedDescription)"
            migrationStatus = ""
        }
    }
    
    private func checkAndDownloadNewBlob(_ blob: String) async {
        let name = displayName(for: blob)
        
        if songlistExists(name) {
            duplicateSonglistName = name
            pendingImportAction = {
                await self.performNewBlobDownload(blob, replacing: true)
            }
            showDuplicateAlert = true
        } else {
            await performNewBlobDownload(blob, replacing: false)
        }
    }
    
    private func performNewBlobDownload(_ blob: String, replacing: Bool) async {
        let name = displayName(for: blob)
        
        do {
            // Delete existing if replacing
            if replacing {
                deleteExistingSonglist(name)
            }
            
            let songlist = try await azureService.downloadAndImportSonglist(
                name: blob,
                documentService: documentService,
                songlistService: songlistService
            )
            errorMessage = "✅ Downloaded '\(songlist.name)' with \(songlist.songCount) songs"
        } catch {
            errorMessage = "Download failed: \(error.localizedDescription)"
        }
    }
    
    private func uploadSonglist(_ songlist: Songlist) async {
        do {
            try await azureService.uploadSonglist(songlist, documentService: documentService)
            await loadNewBlobs()
            errorMessage = "✅ Uploaded '\(songlist.name)'"
        } catch {
            errorMessage = "Upload failed: \(error.localizedDescription)"
        }
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        else if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        else { return String(format: "%.1f MB", Double(bytes) / (1024 * 1024)) }
    }
}
