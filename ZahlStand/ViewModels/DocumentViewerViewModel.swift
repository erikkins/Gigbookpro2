import Foundation
import SwiftUI
import PDFKit
import Combine

@MainActor
class DocumentViewerViewModel: ObservableObject {
    @Published var currentSong: Song?
    @Published var currentSonglist: Songlist?
    @Published var currentDocument: PDFDocument?
    @Published var currentSongIndex: Int = 0
    @Published var showingInfo: Bool = false
    @Published var midiConnected: Bool = false
    @Published var isSingleSongMode: Bool = false
    @Published var isLibraryMode: Bool = false
    @Published var librarySongs: [Song] = []

    let documentService: DocumentService
    let songlistService: SonglistService
    let midiService: MIDIService

    private var cancellables = Set<AnyCancellable>()
    
    init(documentService: DocumentService, songlistService: SonglistService, midiService: MIDIService) {
        self.documentService = documentService
        self.songlistService = songlistService
        self.midiService = midiService
        setupBindings()
    }
    
    var totalSongs: Int {
        if isSingleSongMode { return 1 }
        if isLibraryMode { return librarySongs.count }
        return currentSonglist?.songCount ?? 0
    }
    var hasNextSong: Bool { (isLibraryMode || !isSingleSongMode) && currentSongIndex < totalSongs - 1 }
    var hasPreviousSong: Bool { (isLibraryMode || !isSingleSongMode) && currentSongIndex > 0 }
    
    private func setupBindings() {
        songlistService.$activeSonglist.sink { [weak self] songlist in
            guard let self = self else { return }
            if songlist != nil {
                self.isSingleSongMode = false
                self.currentSonglist = songlist
                self.loadSong(at: 0)
            }
        }.store(in: &cancellables)
        
        midiService.$isConnected.assign(to: &$midiConnected)
    }
    
    func nextSong() {
        guard hasNextSong else { return }
        if isLibraryMode {
            loadLibrarySong(at: currentSongIndex + 1)
        } else {
            loadSong(at: currentSongIndex + 1)
        }
    }

    func previousSong() {
        guard hasPreviousSong else { return }
        if isLibraryMode {
            loadLibrarySong(at: currentSongIndex - 1)
        } else {
            loadSong(at: currentSongIndex - 1)
        }
    }

    func jumpToSong(at index: Int) {
        if isLibraryMode {
            loadLibrarySong(at: index)
        } else {
            loadSong(at: index)
        }
    }

    func loadSong(at index: Int) {
        guard let songlist = currentSonglist else { return }
        guard index >= 0, index < songlist.songCount else { return }

        currentSongIndex = index

        guard let song = songlist.song(at: index) else { return }
        currentSong = song

        if song.isPDF {
            currentDocument = documentService.loadPDFDocument(for: song)
        } else {
            currentDocument = nil
        }

        if song.hasMIDIProgramChange {
            midiService.sendProgramChange(for: song)
        }
    }

    private func loadLibrarySong(at index: Int) {
        guard index >= 0, index < librarySongs.count else { return }

        currentSongIndex = index
        let song = librarySongs[index]
        currentSong = song

        if song.isPDF {
            currentDocument = documentService.loadPDFDocument(for: song)
        } else {
            currentDocument = nil
        }

        if song.hasMIDIProgramChange {
            midiService.sendProgramChange(for: song)
        }
    }
    
    // Load a songlist directly (for iPhone navigation)
    func loadSonglist(_ songlist: Songlist) {
        isSingleSongMode = false
        isLibraryMode = false
        librarySongs = []
        currentSonglist = songlist
        currentSonglist?.documentService = documentService
        loadSong(at: 0)
    }
    
    func loadSingleSong(_ song: Song) {
        isSingleSongMode = true
        isLibraryMode = false
        librarySongs = []
        currentSonglist = nil
        currentSong = song
        currentSongIndex = 0

        if song.isPDF {
            currentDocument = documentService.loadPDFDocument(for: song)
        } else {
            currentDocument = nil
        }

        if song.hasMIDIProgramChange {
            midiService.sendProgramChange(for: song)
        }
    }

    /// Load a song from the library with navigation through all library songs
    func loadSongFromLibrary(_ song: Song, allSongs: [Song]) {
        isSingleSongMode = false
        isLibraryMode = true
        librarySongs = allSongs
        currentSonglist = nil

        // Find the index of the selected song
        if let index = allSongs.firstIndex(where: { $0.id == song.id }) {
            currentSongIndex = index
        } else {
            currentSongIndex = 0
        }

        currentSong = song

        if song.isPDF {
            currentDocument = documentService.loadPDFDocument(for: song)
        } else {
            currentDocument = nil
        }

        if song.hasMIDIProgramChange {
            midiService.sendProgramChange(for: song)
        }
    }
    
    func toggleInfo() {
        withAnimation {
            showingInfo.toggle()
        }
        
        if showingInfo {
            Task {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                withAnimation {
                    self.showingInfo = false
                }
            }
        }
    }
    
    func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls { documentService.importDocument(from: url) { _ in } }
        case .failure: break
        }
    }
}
