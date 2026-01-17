import SwiftUI
import PDFKit
import WebKit

struct DocumentViewer: View {
    @StateObject private var viewModel: DocumentViewerViewModel
    @State private var showingMIDISettings = false
    @State private var showingQuickJump = false

    let midiService: MIDIService
    private let initialSong: Song?
    private let initialSonglist: Songlist?
    private let initialLibrarySongs: [Song]?

    init(documentService: DocumentService, songlistService: SonglistService, midiService: MIDIService) {
        _viewModel = StateObject(wrappedValue: DocumentViewerViewModel(
            documentService: documentService,
            songlistService: songlistService,
            midiService: midiService
        ))
        self.midiService = midiService
        self.initialSong = nil
        self.initialSonglist = nil
        self.initialLibrarySongs = nil
    }

    init(documentService: DocumentService, songlistService: SonglistService, midiService: MIDIService, initialSong: Song) {
        _viewModel = StateObject(wrappedValue: DocumentViewerViewModel(
            documentService: documentService,
            songlistService: songlistService,
            midiService: midiService
        ))
        self.midiService = midiService
        self.initialSong = initialSong
        self.initialSonglist = nil
        self.initialLibrarySongs = nil
    }

    init(documentService: DocumentService, songlistService: SonglistService, midiService: MIDIService, initialSong: Song, initialLibrarySongs: [Song]) {
        _viewModel = StateObject(wrappedValue: DocumentViewerViewModel(
            documentService: documentService,
            songlistService: songlistService,
            midiService: midiService
        ))
        self.midiService = midiService
        self.initialSong = initialSong
        self.initialSonglist = nil
        self.initialLibrarySongs = initialLibrarySongs
    }

    init(documentService: DocumentService, songlistService: SonglistService, midiService: MIDIService, initialSonglist: Songlist) {
        _viewModel = StateObject(wrappedValue: DocumentViewerViewModel(
            documentService: documentService,
            songlistService: songlistService,
            midiService: midiService
        ))
        self.midiService = midiService
        self.initialSong = nil
        self.initialSonglist = initialSonglist
        self.initialLibrarySongs = nil
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(UIColor.systemBackground)
                
                if let song = viewModel.currentSong {
                    ZStack(alignment: .leading) {
                        if song.isPDF, let document = viewModel.currentDocument {
                            PDFContainerView(
                                document: document,
                                onPrevious: { viewModel.previousSong() },
                                onNext: { viewModel.nextSong() }
                            )
                        } else if song.isWord, let filePath = song.filePath {
                            WordContainerView(
                                url: filePath,
                                onPrevious: { viewModel.previousSong() },
                                onNext: { viewModel.nextSong() }
                            )
                        } else {
                            UnsupportedDocumentView(song: song)
                        }
                        
                        PunchHoleView()
                    }
                    
                    if !viewModel.isSingleSongMode || viewModel.isLibraryMode {
                        navigationOverlay(geometry: geometry)
                    }
                } else {
                    WelcomeView()
                }
            }
            .gesture(navigationGestures(geometry: geometry))
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if let song = viewModel.currentSong {
                    Text(song.title)
                        .font(.headline)
                        .lineLimit(1)
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    if (!viewModel.isSingleSongMode || viewModel.isLibraryMode) && viewModel.currentSong != nil {
                        Button { showingQuickJump = true } label: {
                            Image(systemName: "list.number")
                        }
                    }
                    Button { showingMIDISettings = true } label: {
                        Image(systemName: viewModel.midiConnected ? "pianokeys.inverse" : "pianokeys")
                            .foregroundColor(viewModel.midiConnected ? .green : .primary)
                    }
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMIDISettings) {
            MIDISettingsView(midiService: midiService)
        }
        .sheet(isPresented: $showingQuickJump) {
            QuickJumpView(viewModel: viewModel, isPresented: $showingQuickJump)
        }
        .onAppear {
            if let song = initialSong, let librarySongs = initialLibrarySongs {
                viewModel.loadSongFromLibrary(song, allSongs: librarySongs)
            } else if let song = initialSong {
                viewModel.loadSingleSong(song)
            } else if let songlist = initialSonglist {
                viewModel.loadSonglist(songlist)
            } else {
                showSidebarIfNeeded()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .viewSingleSong)) { notification in
            if let song = notification.object as? Song {
                viewModel.loadSingleSong(song)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .viewSongFromLibrary)) { notification in
            if let userInfo = notification.userInfo,
               let song = userInfo["song"] as? Song,
               let allSongs = userInfo["allSongs"] as? [Song] {
                viewModel.loadSongFromLibrary(song, allSongs: allSongs)
            }
        }
    }
    
    private func showSidebarIfNeeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let splitVC = findSplitViewController(in: window.rootViewController) {
                splitVC.show(.primary)
            }
        }
    }
    
    private func findSplitViewController(in vc: UIViewController?) -> UISplitViewController? {
        if let split = vc as? UISplitViewController {
            return split
        }
        for child in vc?.children ?? [] {
            if let found = findSplitViewController(in: child) {
                return found
            }
        }
        return nil
    }
    
    private func navigationOverlay(geometry: GeometryProxy) -> some View {
        VStack {
            Spacer()
            HStack {
                if viewModel.hasPreviousSong {
                    Button { viewModel.previousSong() } label: {
                        Image(systemName: "chevron.left.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    .padding(.leading, 20)
                }
                
                Spacer()
                
                Button { showingQuickJump = true } label: {
                    Text("\(viewModel.currentSongIndex + 1) / \(viewModel.totalSongs)")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(20)
                }
                
                Spacer()
                
                if viewModel.hasNextSong {
                    Button { viewModel.nextSong() } label: {
                        Image(systemName: "chevron.right.circle.fill")
                            .font(.system(size: 44))
                            .foregroundColor(.white)
                            .shadow(radius: 4)
                    }
                    .padding(.trailing, 20)
                }
            }
            .padding(.bottom, 40)
        }
    }
    
    private func navigationGestures(geometry: GeometryProxy) -> some Gesture {
        DragGesture(minimumDistance: 50)
            .onEnded { value in
                let horizontal = value.translation.width
                if horizontal > 100 && viewModel.hasPreviousSong {
                    viewModel.previousSong()
                } else if horizontal < -100 && viewModel.hasNextSong {
                    viewModel.nextSong()
                }
            }
    }
}

// MARK: - Welcome View

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "music.note.list")
                .font(.system(size: 80))
                .foregroundColor(.accentColor)
            
            Text("Welcome to GigbookPro2")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Select a song or songlist from the sidebar to get started")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            Button {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let window = windowScene.windows.first,
                   let splitVC = findSplitViewController(in: window.rootViewController) {
                    splitVC.show(.primary)
                }
            } label: {
                Label("Open Song Library", systemImage: "sidebar.left")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.top, 8)
        }
    }
    
    private func findSplitViewController(in vc: UIViewController?) -> UISplitViewController? {
        if let split = vc as? UISplitViewController {
            return split
        }
        for child in vc?.children ?? [] {
            if let found = findSplitViewController(in: child) {
                return found
            }
        }
        return nil
    }
}

// MARK: - Quick Jump View

struct QuickJumpView: View {
    @ObservedObject var viewModel: DocumentViewerViewModel
    @Binding var isPresented: Bool

    private var songs: [Song] {
        if viewModel.isLibraryMode {
            return viewModel.librarySongs
        } else if let songlist = viewModel.currentSonglist {
            return songlist.songs
        }
        return []
    }

    private var title: String {
        if viewModel.isLibraryMode {
            return "Song Library"
        }
        return viewModel.currentSonglist?.name ?? "Songlist"
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                    Button {
                        viewModel.jumpToSong(at: index)
                        isPresented = false
                    } label: {
                        HStack {
                            Text("\(index + 1)")
                                .font(.headline.monospacedDigit())
                                .foregroundColor(.secondary)
                                .frame(width: 36, alignment: .trailing)

                            if index == viewModel.currentSongIndex {
                                Image(systemName: "play.fill")
                                    .foregroundColor(.accentColor)
                                    .font(.caption)
                            } else {
                                Spacer().frame(width: 16)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .font(.body)
                                    .foregroundColor(index == viewModel.currentSongIndex ? .accentColor : .primary)

                                if let artist = song.artist {
                                    Text(artist)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            if song.hasMIDIProgramChange {
                                Image(systemName: "pianokeys")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .listRowBackground(index == viewModel.currentSongIndex ?
                        Color.accentColor.opacity(0.1) : Color.clear)
                }
            }
            .listStyle(.plain)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }
}

// MARK: - Base Key Command Controller

class KeyCommandController: UIViewController {
    var onPrevious: (() -> Void)?
    var onNext: (() -> Void)?
    var onScrollUp: (() -> Void)?
    var onScrollDown: (() -> Void)?
    
    override var canBecomeFirstResponder: Bool { true }
    
    private var firstResponderTimer: Timer?
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
        startFirstResponderTimer()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        stopFirstResponderTimer()
    }
    
    private func startFirstResponderTimer() {
        // Only reassert first responder if no other view controller is presented
        firstResponderTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // Don't steal focus if there's a presented view controller (sheet/modal)
            if self.presentedViewController != nil {
                return
            }
            // Don't steal focus if there's any presented controller in the hierarchy
            if self.isAnyViewControllerPresented() {
                return
            }
            if !self.isFirstResponder && self.view.window != nil {
                self.becomeFirstResponder()
            }
        }
    }
    
    private func isAnyViewControllerPresented() -> Bool {
        // Check if any view controller in the window has a presented view controller
        guard let window = view.window else { return false }
        return checkForPresentedViewController(in: window.rootViewController)
    }
    
    private func checkForPresentedViewController(in vc: UIViewController?) -> Bool {
        guard let vc = vc else { return false }
        if vc.presentedViewController != nil {
            return true
        }
        for child in vc.children {
            if checkForPresentedViewController(in: child) {
                return true
            }
        }
        return false
    }
    
    private func stopFirstResponderTimer() {
        firstResponderTimer?.invalidate()
        firstResponderTimer = nil
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        becomeFirstResponder()
    }
    
    override var keyCommands: [UIKeyCommand]? {
        var commands: [UIKeyCommand] = []
        
        let leftArrow = UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(handlePrevious))
        leftArrow.wantsPriorityOverSystemBehavior = true
        commands.append(leftArrow)
        
        let rightArrow = UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(handleNext))
        rightArrow.wantsPriorityOverSystemBehavior = true
        commands.append(rightArrow)
        
        let upArrow = UIKeyCommand(input: UIKeyCommand.inputUpArrow, modifierFlags: [], action: #selector(handleScrollUp))
        upArrow.wantsPriorityOverSystemBehavior = true
        commands.append(upArrow)
        
        let downArrow = UIKeyCommand(input: UIKeyCommand.inputDownArrow, modifierFlags: [], action: #selector(handleScrollDown))
        downArrow.wantsPriorityOverSystemBehavior = true
        commands.append(downArrow)
        
        return commands
    }
    
    @objc func handlePrevious() { onPrevious?() }
    @objc func handleNext() { onNext?() }
    @objc func handleScrollUp() { onScrollUp?() }
    @objc func handleScrollDown() { onScrollDown?() }
}

// MARK: - PDF Container

struct PDFContainerView: UIViewControllerRepresentable {
    let document: PDFDocument
    let onPrevious: () -> Void
    let onNext: () -> Void
    
    func makeUIViewController(context: Context) -> PDFKeyCommandController {
        let vc = PDFKeyCommandController()
        vc.document = document
        vc.onPrevious = onPrevious
        vc.onNext = onNext
        return vc
    }
    
    func updateUIViewController(_ uiViewController: PDFKeyCommandController, context: Context) {
        if uiViewController.pdfView.document != document {
            uiViewController.pdfView.document = document
            uiViewController.pdfView.goToFirstPage(nil)
            uiViewController.scrollUpToHideMargin()
        }
        uiViewController.onPrevious = onPrevious
        uiViewController.onNext = onNext
    }
}

class PDFKeyCommandController: KeyCommandController {
    let pdfView = NonInteractivePDFView()
    private let topMarginOffset: CGFloat = 72
    
    var document: PDFDocument? {
        didSet { 
            pdfView.document = document
            scrollUpToHideMargin()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = document
        
        view.addSubview(pdfView)
        NSLayoutConstraint.activate([
            pdfView.topAnchor.constraint(equalTo: view.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            pdfView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        onScrollUp = { [weak self] in self?.scrollUp() }
        onScrollDown = { [weak self] in self?.scrollDown() }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scrollUpToHideMargin()
    }
    
    func scrollUpToHideMargin() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self = self,
                  let scrollView = self.findScrollView(in: self.pdfView) else { return }
            
            let scaledOffset = self.topMarginOffset * self.pdfView.scaleFactor
            let newY = min(scaledOffset, scrollView.contentSize.height - scrollView.bounds.height)
            
            if newY > 0 {
                scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: newY), animated: false)
            }
        }
    }
    
    private func scrollUp() {
        guard let scrollView = findScrollView(in: pdfView) else { return }
        let newY = max(scrollView.contentOffset.y - scrollView.bounds.height * 0.8, 0)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: newY), animated: true)
    }
    
    private func scrollDown() {
        guard let scrollView = findScrollView(in: pdfView) else { return }
        let maxY = max(scrollView.contentSize.height - scrollView.bounds.height, 0)
        let newY = min(scrollView.contentOffset.y + scrollView.bounds.height * 0.8, maxY)
        scrollView.setContentOffset(CGPoint(x: scrollView.contentOffset.x, y: newY), animated: true)
    }
    
    private func findScrollView(in view: UIView) -> UIScrollView? {
        if let scrollView = view as? UIScrollView { return scrollView }
        for subview in view.subviews {
            if let found = findScrollView(in: subview) { return found }
        }
        return nil
    }
}

class NonInteractivePDFView: PDFView {
    override var canBecomeFirstResponder: Bool { false }
}

// MARK: - Word Container

struct WordContainerView: UIViewControllerRepresentable {
    let url: URL
    let onPrevious: () -> Void
    let onNext: () -> Void
    
    func makeUIViewController(context: Context) -> WordKeyCommandController {
        let vc = WordKeyCommandController()
        vc.url = url
        vc.onPrevious = onPrevious
        vc.onNext = onNext
        return vc
    }
    
    func updateUIViewController(_ uiViewController: WordKeyCommandController, context: Context) {
        if uiViewController.url != url {
            uiViewController.url = url
            uiViewController.loadDocument()
        }
        uiViewController.onPrevious = onPrevious
        uiViewController.onNext = onNext
    }
}

class WordKeyCommandController: KeyCommandController, WKNavigationDelegate {
    let webView = NonInteractiveWebView()
    var url: URL?
    private let topMarginOffset: Int = 72
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.backgroundColor = .white
        webView.navigationDelegate = self
        
        view.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.topAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])
        
        loadDocument()
        
        onScrollUp = { [weak self] in self?.scrollUp() }
        onScrollDown = { [weak self] in self?.scrollDown() }
    }
    
    func loadDocument() {
        guard let url = url else { return }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let js = "window.scrollTo(0, \(topMarginOffset));"
        webView.evaluateJavaScript(js, completionHandler: nil)
    }
    
    private func scrollUp() {
        webView.evaluateJavaScript("window.scrollBy(0, -window.innerHeight * 0.8);", completionHandler: nil)
    }
    
    private func scrollDown() {
        webView.evaluateJavaScript("window.scrollBy(0, window.innerHeight * 0.8);", completionHandler: nil)
    }
}

class NonInteractiveWebView: WKWebView {
    override var canBecomeFirstResponder: Bool { false }
}

// MARK: - Unsupported Document

struct UnsupportedDocumentView: View {
    let song: Song
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "doc.questionmark.fill")
                .font(.system(size: 80))
                .foregroundColor(.orange)
            
            Text(song.title)
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Unsupported document type: \(song.fileExtension.uppercased())")
                .foregroundColor(.secondary)
        }
    }
}
