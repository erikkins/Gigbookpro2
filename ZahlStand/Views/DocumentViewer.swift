import SwiftUI
import PDFKit

/// Context for presenting the annotation editor
struct AnnotationEditorContext: Identifiable {
    let id = UUID()
    let pageIndex: Int
    let relativeX: CGFloat
    let relativeY: CGFloat
    let existingAnnotation: PDFAnnotation?
}

struct DocumentViewer: View {
    @StateObject private var viewModel: DocumentViewerViewModel
    @EnvironmentObject var overridesService: LocalMIDIOverridesService
    @EnvironmentObject var annotationService: AnnotationService
    @State private var showingMIDISettings = false
    @State private var showingQuickJump = false
    @State private var showingAnnotationProfiles = false
    @State private var annotationEditorContext: AnnotationEditorContext?
    @State private var pdfViewController: PDFKeyCommandController?

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
                        if let document = viewModel.currentDocument {
                            PDFContainerView(
                                document: document,
                                onPrevious: { viewModel.previousSong() },
                                onNext: { viewModel.nextSong() },
                                onLongPress: { pageIndex, x, y in
                                    annotationEditorContext = AnnotationEditorContext(
                                        pageIndex: pageIndex,
                                        relativeX: x,
                                        relativeY: y,
                                        existingAnnotation: nil
                                    )
                                },
                                onViewControllerReady: { vc in
                                    pdfViewController = vc
                                }
                            )

                            // Annotation overlay
                            if let vc = pdfViewController {
                                AnnotationOverlayView(
                                    annotationService: annotationService,
                                    pdfViewController: vc,
                                    onAnnotationTap: { annotation in
                                        annotationEditorContext = AnnotationEditorContext(
                                            pageIndex: annotation.pageIndex,
                                            relativeX: annotation.relativeX,
                                            relativeY: annotation.relativeY,
                                            existingAnnotation: annotation
                                        )
                                    }
                                )
                            }
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
        }
        .ignoresSafeArea(.container, edges: .top)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                if let song = viewModel.currentSong, let bpm = song.bpmValue {
                    HStack {
                        TempoIndicatorView(bpm: bpm)
                    }
                }
            }
            ToolbarItemGroup(placement: .navigationBarTrailing) {
                if (!viewModel.isSingleSongMode || viewModel.isLibraryMode) && viewModel.currentSong != nil {
                    Button { showingQuickJump = true } label: {
                        Image(systemName: "list.number")
                    }
                }
                if viewModel.currentSong != nil {
                    Button { showingAnnotationProfiles = true } label: {
                        Image(systemName: annotationService.hasAnnotations ? "note.text" : "note.text.badge.plus")
                            .foregroundColor(annotationService.hasAnnotations ? .orange : .primary)
                    }
                }
                Button { showingMIDISettings = true } label: {
                    Image(systemName: viewModel.midiConnected ? "pianokeys.inverse" : "pianokeys")
                        .foregroundColor(viewModel.midiConnected ? .green : .primary)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingMIDISettings) {
            MIDISettingsView(midiService: midiService, overridesService: overridesService)
        }
        .sheet(isPresented: $showingQuickJump) {
            QuickJumpView(viewModel: viewModel, isPresented: $showingQuickJump)
        }
        .sheet(item: $annotationEditorContext) { context in
            AnnotationEditorView(
                annotationService: annotationService,
                pageIndex: context.pageIndex,
                relativeX: context.relativeX,
                relativeY: context.relativeY,
                existingAnnotation: context.existingAnnotation
            )
        }
        .sheet(isPresented: $showingAnnotationProfiles) {
            AnnotationProfilePicker(annotationService: annotationService)
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
            // Load annotations for current song
            if let song = viewModel.currentSong {
                annotationService.loadAnnotations(for: song.fullFileName)
            }
        }
        .onChange(of: viewModel.currentSong?.id) { _ in
            // Load annotations when song changes
            if let song = viewModel.currentSong {
                annotationService.loadAnnotations(for: song.fullFileName)
            } else {
                annotationService.clearCurrentAnnotations()
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
    
}

// MARK: - Tempo Indicator

struct TempoIndicatorView: View {
    let bpm: Int
    @State private var isAnimating = false
    @State private var isPaused = false

    private var pulseDuration: Double {
        60.0 / Double(bpm)
    }

    var body: some View {
        Button {
            isPaused.toggle()
            if !isPaused {
                // Restart animation when unpausing
                isAnimating = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    isAnimating = true
                }
            }
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)
                    .scaleEffect(isPaused ? 1.0 : (isAnimating ? 1.15 : 1.0), anchor: .center)
                    .opacity(isPaused ? 0.4 : (isAnimating ? 1.0 : 0.3))
                    .animation(
                        isPaused ? .none : .easeInOut(duration: pulseDuration / 2).repeatForever(autoreverses: true),
                        value: isAnimating
                    )
                    .id("tempo-ball-\(bpm)")

                Text("\(bpm)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .onAppear {
            startAnimation()
        }
        .onChange(of: bpm) { _ in
            // Reset animation when BPM changes (different song)
            isAnimating = false
            isPaused = false
            startAnimation()
        }
    }

    private func startAnimation() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            isAnimating = true
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
    var onLongPress: ((Int, CGFloat, CGFloat) -> Void)?
    var onViewControllerReady: ((PDFKeyCommandController) -> Void)?

    func makeUIViewController(context: Context) -> PDFKeyCommandController {
        let vc = PDFKeyCommandController()
        vc.document = document
        vc.onPrevious = onPrevious
        vc.onNext = onNext
        vc.onLongPress = onLongPress
        DispatchQueue.main.async {
            onViewControllerReady?(vc)
        }
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
        uiViewController.onLongPress = onLongPress
    }
}

class PDFKeyCommandController: KeyCommandController, UIGestureRecognizerDelegate {
    let pdfView = NonInteractivePDFView()
    private let topMarginOffset: CGFloat = 36
    private var selectionOverlay: SelectionBlockingOverlay?

    /// Callback for long press annotation creation: (pageIndex, relativeX, relativeY)
    var onLongPress: ((Int, CGFloat, CGFloat) -> Void)?

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

        // Add overlay to block text selection while allowing scroll
        selectionOverlay = SelectionBlockingOverlay(frame: .zero)
        selectionOverlay!.translatesAutoresizingMaskIntoConstraints = false
        selectionOverlay!.backgroundColor = .clear
        selectionOverlay!.scrollView = findScrollView(in: pdfView)
        view.addSubview(selectionOverlay!)
        NSLayoutConstraint.activate([
            selectionOverlay!.topAnchor.constraint(equalTo: view.topAnchor),
            selectionOverlay!.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            selectionOverlay!.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            selectionOverlay!.trailingAnchor.constraint(equalTo: view.trailingAnchor)
        ])

        onScrollUp = { [weak self] in self?.scrollUp() }
        onScrollDown = { [weak self] in self?.scrollDown() }

        // Add swipe gestures for song navigation
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeLeft))
        swipeLeft.direction = .left
        swipeLeft.delegate = self
        selectionOverlay!.addGestureRecognizer(swipeLeft)

        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleSwipeRight))
        swipeRight.direction = .right
        swipeRight.delegate = self
        selectionOverlay!.addGestureRecognizer(swipeRight)

        // Add long press gesture for annotation creation
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.delegate = self
        selectionOverlay!.addGestureRecognizer(longPress)
    }

    @objc private func handleSwipeLeft() {
        onNext?()
    }

    @objc private func handleSwipeRight() {
        onPrevious?()
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        // Convert from overlay coordinates to PDF view coordinates
        let overlayLocation = gesture.location(in: gesture.view)
        let location = gesture.view?.convert(overlayLocation, to: pdfView) ?? overlayLocation
        if let coords = convertToPageCoordinates(location) {
            onLongPress?(coords.pageIndex, coords.relativeX, coords.relativeY)
        }
    }

    // MARK: - Coordinate Conversion

    /// Convert screen point to PDF page coordinates (pageIndex, relativeX, relativeY)
    func convertToPageCoordinates(_ screenPoint: CGPoint) -> (pageIndex: Int, relativeX: CGFloat, relativeY: CGFloat)? {
        guard let page = pdfView.page(for: screenPoint, nearest: true),
              let document = pdfView.document else { return nil }

        let pageIndex = document.index(for: page)
        let pagePoint = pdfView.convert(screenPoint, to: page)
        let pageBounds = page.bounds(for: .mediaBox)

        // Clamp values to 0.0 - 1.0 range
        let relativeX = max(0, min(1, pagePoint.x / pageBounds.width))
        let relativeY = max(0, min(1, pagePoint.y / pageBounds.height))

        return (pageIndex, relativeX, relativeY)
    }

    /// Convert PDF page coordinates back to screen coordinates
    func convertToScreenCoordinates(pageIndex: Int, relativeX: CGFloat, relativeY: CGFloat) -> CGPoint? {
        guard let document = pdfView.document,
              let page = document.page(at: pageIndex) else { return nil }

        let pageBounds = page.bounds(for: .mediaBox)
        let pagePoint = CGPoint(
            x: relativeX * pageBounds.width,
            y: relativeY * pageBounds.height
        )
        return pdfView.convert(pagePoint, from: page)
    }

    // Allow swipe gestures to work simultaneously with scroll view
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Ensure overlay has scroll view reference
        if selectionOverlay?.scrollView == nil {
            selectionOverlay?.scrollView = findScrollView(in: pdfView)
        }
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

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        // Block all selection and copy-related actions
        return false
    }
}

/// Overlay that intercepts taps but passes scroll gestures through
class SelectionBlockingOverlay: UIView, UIGestureRecognizerDelegate {
    private var panGesture: UIPanGestureRecognizer!
    weak var scrollView: UIScrollView?
    private var lastVelocity: CGFloat = 0
    private var displayLink: CADisplayLink?
    private var decelerationVelocity: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    private func setup() {
        // Add pan gesture to forward scrolling
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.delegate = self
        addGestureRecognizer(panGesture)
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let scrollView = scrollView else { return }

        let translation = gesture.translation(in: self)
        let velocity = gesture.velocity(in: self)

        switch gesture.state {
        case .began:
            stopDeceleration()
        case .changed:
            var offset = scrollView.contentOffset
            offset.y -= translation.y
            offset.y = max(0, min(offset.y, scrollView.contentSize.height - scrollView.bounds.height))
            scrollView.contentOffset = offset
            gesture.setTranslation(.zero, in: self)
            lastVelocity = velocity.y
        case .ended, .cancelled:
            // Start momentum scrolling
            startDeceleration(velocity: -velocity.y)
        default:
            break
        }
    }

    private func startDeceleration(velocity: CGFloat) {
        decelerationVelocity = velocity
        displayLink = CADisplayLink(target: self, selector: #selector(updateDeceleration))
        displayLink?.add(to: .main, forMode: .common)
    }

    private func stopDeceleration() {
        displayLink?.invalidate()
        displayLink = nil
        decelerationVelocity = 0
    }

    @objc private func updateDeceleration() {
        guard let scrollView = scrollView else {
            stopDeceleration()
            return
        }

        // Apply deceleration
        let deceleration: CGFloat = 0.95
        decelerationVelocity *= deceleration

        // Stop if velocity is very small
        if abs(decelerationVelocity) < 1 {
            stopDeceleration()
            return
        }

        // Update scroll position
        var offset = scrollView.contentOffset
        offset.y += decelerationVelocity * CGFloat(displayLink?.duration ?? 0.016)
        offset.y = max(0, min(offset.y, scrollView.contentSize.height - scrollView.bounds.height))
        scrollView.contentOffset = offset

        // Stop at bounds
        if offset.y <= 0 || offset.y >= scrollView.contentSize.height - scrollView.bounds.height {
            stopDeceleration()
        }
    }

    // Allow pan gesture to work simultaneously with other gestures
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Return self to capture touches (blocking PDF text selection)
        return self
    }

    deinit {
        stopDeceleration()
    }
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
