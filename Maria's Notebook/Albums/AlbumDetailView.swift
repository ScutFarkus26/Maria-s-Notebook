// AlbumDetailView.swift
// The reading screen for one album: PDF viewer with the outline sidebar
// (Mac) or Contents sheet (iOS), find-in-album bar, thumbnail strip,
// bookmarks, per-page notes, text highlighting, Pencil markup (iOS),
// Related Lessons, lesson summaries, PDF export, go-to-page, and printing.
// Exposes AlbumFocusActions so the macOS menu bar drives all of it, and
// saves/restores the reading position that syncs across devices.

import CoreData
import SwiftUI
import PDFKit
import UniformTypeIdentifiers
#if os(iOS)
import PencilKit
#endif

struct AlbumDetailView: View {
    @Environment(AlbumLibrary.self) private var library
    @Environment(AlbumsNavModel.self) private var nav
    @Environment(AlbumIntelligence.self) private var intelligence
    @Environment(\.managedObjectContext) private var context
    @Environment(\.openWindow) private var openWindow
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    let album: Album

    // Scoped to this album at init rather than fetching every row and
    // filtering in Swift. Both call sites key the view on `album.id`, so the
    // predicate is rebuilt whenever the album changes.
    @FetchRequest private var bookmarks: FetchedResults<CDAlbumBookmark>
    @FetchRequest private var notes: FetchedResults<CDAlbumPageNote>
    @FetchRequest private var highlights: FetchedResults<CDAlbumHighlight>

    init(album: Album) {
        self.album = album
        let scope = NSPredicate(format: "albumID == %@", album.id)
        let unsorted: [NSSortDescriptor] = []
        _bookmarks = FetchRequest(sortDescriptors: unsorted, predicate: scope)
        _notes = FetchRequest(sortDescriptors: unsorted, predicate: scope)
        _highlights = FetchRequest(sortDescriptors: unsorted, predicate: scope)
    }

    @State private var currentPage = 0
    @State private var jump: AlbumPageJump?
    @State private var proxy = AlbumPDFViewerProxy()
    @State private var showNotesPopover = false
    @State private var showRelatedPopover = false
    @State private var showNotebookLessonPopover = false
    @State private var showOutlineSheet = false
    @State private var showGoToPage = false
    @State private var goToPageText = ""
    @State private var showThumbnails = false
    @State private var summary: AlbumSummaryState?
    @State private var didRestorePosition = false

    // Reading-position persistence. Both writes are debounced: flipping
    // through a lesson used to fire two Core Data saves — and two CloudKit
    // pushes — per page turn.
    @State private var positionSaveTask: Task<Void, Never>?
    @State private var lastRecordedLessonTitle: String?

    // Find in album
    @State private var showFindBar = false
    @State private var findText = ""
    @State private var findMatches: [PDFSelection] = []
    @State private var findIndex = 0
    @FocusState private var findFieldFocused: Bool

    // Export
    @State private var exportDocument: PDFExportDocument?
    @State private var showExporter = false

    #if os(iOS)
    @State private var ink = InkController()
    @State private var inkSaveTask: Task<Void, Never>?
    #endif

    private var currentLesson: AlbumLessonRef? { album.lesson(forPage: currentPage) }
    private var albumHighlights: [CDAlbumHighlight] { Array(highlights) }

    var body: some View {
        content
            .navigationTitle(album.title)
            #if os(macOS)
            .navigationSubtitle(currentLesson?.title ?? "")
            .toolbar(id: "album") { toolbarContent }
            .focusedSceneValue(\.albumActions, focusActions)
            #else
            .toolbar { iosToolbarContent }
            #endif
            .onAppear {
                library.markSeen(album)
                album.applyHighlights(albumHighlights)
                loadInk()
                consumeTarget()
                restorePositionIfNeeded()
            }
            .onChange(of: nav.pageTarget) { consumeTarget() }
            .onChange(of: albumHighlights) { album.applyHighlights(albumHighlights) }
            .onChange(of: currentPage) {
                didRestorePosition = true
                schedulePositionSave()
            }
            .onDisappear {
                // Leaving mid-debounce still records where the guide got to.
                positionSaveTask?.cancel()
                positionSaveTask = nil
                persistPosition(pageIndex: currentPage)
            }
            .alert("Go to Page", isPresented: $showGoToPage) {
                TextField("Page number", text: $goToPageText)
                Button("Go") {
                    if let page = Int(goToPageText), (1...album.pageCount).contains(page) {
                        goTo(pageIndex: page - 1)
                    }
                    goToPageText = ""
                }
                Button("Cancel", role: .cancel) { goToPageText = "" }
            } message: {
                Text("Enter a page from 1 to \(album.pageCount).")
            }
            .sheet(item: $summary) { state in
                AlbumSummarySheet(state: state, album: album) { text, lesson in
                    AlbumUserDataStore.addNote(albumID: album.id, pageIndex: lesson.pageIndex,
                                     lessonTitle: lesson.title, text: text, in: context)
                }
            }
            .fileExporter(isPresented: $showExporter, document: exportDocument,
                          contentType: .pdf, defaultFilename: exportFilename) { _ in }
            #if os(iOS)
            .sheet(isPresented: $showOutlineSheet) {
                NavigationStack {
                    AlbumOutlineListView(album: album, currentPage: currentPage) { node in
                        showOutlineSheet = false
                        goTo(pageIndex: node.pageIndex)
                    }
                    .navigationTitle("Contents")
                    .navigationBarTitleDisplayMode(.inline)
                }
            }
            #endif
    }

    // MARK: Layout

    @ViewBuilder
    private var content: some View {
        #if os(macOS)
        HStack(spacing: 0) {
            AlbumOutlineListView(album: album, currentPage: currentPage) { node in
                goTo(pageIndex: node.pageIndex)
            }
            .frame(width: 265)
            Divider()
            viewerStack
            if showThumbnails {
                Divider()
                ThumbnailStripView(proxy: proxy)
                    .frame(width: 96)
            }
        }
        #else
        VStack(spacing: 0) {
            viewerStack
            if showThumbnails {
                Divider()
                ThumbnailStripView(proxy: proxy)
                    .frame(height: 104)
            }
        }
        #endif
    }

    private var viewerStack: some View {
        viewer
            .safeAreaInset(edge: .top, spacing: 0) {
                if showFindBar { findBar }
            }
    }

    private var viewer: some View {
        #if os(iOS)
        AlbumPDFViewer(document: album.document, currentPageIndex: $currentPage,
                      jump: jump, proxy: proxy, inkController: ink)
            .ignoresSafeArea(edges: .bottom)
        #else
        AlbumPDFViewer(document: album.document, currentPageIndex: $currentPage,
                      jump: jump, proxy: proxy)
            .ignoresSafeArea(edges: .bottom)
        #endif
    }

    // MARK: Find bar

    private var findBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Find in \(album.title)", text: $findText)
                .textFieldStyle(.plain)
                .focused($findFieldFocused)
                .onSubmit { stepFind(1) }
            if !findMatches.isEmpty {
                Text("\(findIndex + 1) of \(findMatches.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if !findText.isEmpty {
                Text("Not found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button { stepFind(-1) } label: { Image(systemName: "chevron.up") }
                .disabled(findMatches.isEmpty)
            Button { stepFind(1) } label: { Image(systemName: "chevron.down") }
                .disabled(findMatches.isEmpty)
            Button("Done") { closeFind() }
                .keyboardShortcut(.escape, modifiers: [])
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .task(id: findText) {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            runFind()
        }
    }

    private func openFind() {
        showFindBar = true
        findFieldFocused = true
    }

    private func runFind() {
        findMatches = proxy.findMatches(findText)
        findIndex = 0
        if let first = findMatches.first {
            proxy.showMatch(first, among: findMatches)
        } else {
            proxy.clearFind()
        }
    }

    private func stepFind(_ delta: Int) {
        guard !findMatches.isEmpty else { return }
        findIndex = (findIndex + delta + findMatches.count) % findMatches.count
        proxy.showMatch(findMatches[findIndex], among: findMatches)
    }

    private func closeFind() {
        showFindBar = false
        findText = ""
        findMatches = []
        proxy.clearFind()
    }

    // MARK: Focus actions (menu bar)

    private var focusActions: AlbumFocusActions {
        AlbumFocusActions(
            albumID: album.id,
            toggleBookmark: { toggleBookmark() },
            addNote: { showNotesPopover = true },
            nextPage: { proxy.nextPage() },
            previousPage: { proxy.previousPage() },
            zoomIn: { proxy.zoomIn() },
            zoomOut: { proxy.zoomOut() },
            actualSize: { proxy.actualSize() },
            goToPage: { showGoToPage = true },
            printPDF: { proxy.printDocument() },
            findInAlbum: { openFind() },
            highlightSelection: { highlightCurrentSelection() },
            exportLesson: { exportCurrentLesson() },
            toggleThumbnails: { showThumbnails.toggle() }
        )
    }

    // MARK: Toolbars

    #if os(macOS)
    /// Customizable toolbar (View ▸ Customize Toolbar…) on the Mac. Split in
    /// two because `@ToolbarContentBuilder` takes at most ten children.
    @ToolbarContentBuilder
    private var toolbarContent: some CustomizableToolbarContent {
        shownToolbarItems
        optionalToolbarItems
    }

    /// The items every guide gets unless they customise them away.
    @ToolbarContentBuilder
    private var shownToolbarItems: some CustomizableToolbarContent {
        ToolbarItem(id: "page-indicator") {
            // Fixed width: a toolbar item that resizes itself while AppKit is
            // measuring the bar trips NSToolbarItemViewer's min/max size assertion.
            Text("p. \(currentPage + 1) of \(album.pageCount)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 120, alignment: .center)
        }
        ToolbarItem(id: "bookmark") { bookmarkButton }
        ToolbarItem(id: "highlight") { highlightButton }
        ToolbarItem(id: "notes") { notesButton }
        ToolbarItem(id: "related") { relatedButton }
        ToolbarItem(id: "notebook-lesson") { notebookLessonButton }
        ToolbarItem(id: "summarize") { summarizeButton }
    }

    /// Hidden until the guide adds them from Customize Toolbar.
    @ToolbarContentBuilder
    private var optionalToolbarItems: some CustomizableToolbarContent {
        ToolbarItem(id: "find", showsByDefault: false) {
            Button { openFind() } label: {
                Label("Find in Album", systemImage: "doc.text.magnifyingglass")
            }
            .help("Find in this album (⌘F)")
        }
        ToolbarItem(id: "thumbnails", showsByDefault: false) {
            Button { showThumbnails.toggle() } label: {
                Label("Thumbnails", systemImage: "rectangle.grid.1x2")
            }
            .help("Show page thumbnails (⌥⌘T)")
        }
        ToolbarItem(id: "export", showsByDefault: false) {
            Button { exportCurrentLesson() } label: {
                Label("Export Lesson…", systemImage: "square.and.arrow.up")
            }
            .help("Export this lesson as a PDF (⇧⌘E)")
        }
        ToolbarItem(id: "open-in-preview", showsByDefault: false) {
            Button {
                NSWorkspace.shared.open(album.url)
            } label: {
                Label("Open in Preview", systemImage: "arrow.up.forward.app")
            }
            .help("Open the PDF in its own app")
        }
    }
    #else
    @ToolbarContentBuilder
    private var iosToolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showOutlineSheet = true
            } label: {
                Label("Contents", systemImage: "list.bullet")
            }
        }
        ToolbarItem {
            if horizontalSizeClass == .regular {
                Text("p. \(currentPage + 1) of \(album.pageCount)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        ToolbarItem { bookmarkButton }
        ToolbarItem { notesButton }
        ToolbarItem { summarizeButton }
        ToolbarItem {
            Menu {
                Button { openFind() } label: {
                    Label("Find in Album", systemImage: "doc.text.magnifyingglass")
                }
                Button { highlightCurrentSelection() } label: {
                    Label("Highlight Selection", systemImage: "highlighter")
                }
                .disabled(!proxy.hasSelection)
                Button { showRelatedPopover = true } label: {
                    Label("Related Lessons", systemImage: "arrow.triangle.branch")
                }
                Button { showNotebookLessonPopover = true } label: {
                    Label("Notebook Lesson", systemImage: "book.closed")
                }
                Toggle(isOn: $showThumbnails) {
                    Label("Page Thumbnails", systemImage: "rectangle.grid.1x2")
                }
                Toggle(isOn: markupBinding) {
                    Label("Markup with Pencil", systemImage: "pencil.tip.crop.circle")
                }
                Button { exportCurrentLesson() } label: {
                    Label("Export Lesson as PDF", systemImage: "square.and.arrow.up")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .popover(isPresented: $showRelatedPopover) {
                RelatedLessonsPanel(album: album, currentPage: currentPage) { target in
                    showRelatedPopover = false
                    openRelated(target)
                }
            }
            .popover(isPresented: $showNotebookLessonPopover) {
                LinkedNotebookLessonsPanel(album: album, currentPage: currentPage) {
                    showNotebookLessonPopover = false
                }
            }
        }
    }

    private var markupBinding: Binding<Bool> {
        Binding(get: { ink.markupEnabled }, set: { ink.markupEnabled = $0 })
    }
    #endif

    private var bookmarkButton: some View {
        Button {
            toggleBookmark()
        } label: {
            Label("Bookmark This Page",
                  systemImage: isBookmarked ? "bookmark.fill" : "bookmark")
                .foregroundStyle(isBookmarked ? album.subject.color : Color.accentColor)
        }
        .help("Bookmark this page (⌘D)")
    }

    private var highlightButton: some View {
        Button {
            highlightCurrentSelection()
        } label: {
            Label("Highlight Selection", systemImage: "highlighter")
        }
        .disabled(!proxy.hasSelection)
        .help("Highlight the selected text (⇧⌘H)")
    }

    private var notesButton: some View {
        Button {
            showNotesPopover = true
        } label: {
            Label("Notes for This Page",
                  systemImage: pageNoteCount > 0 ? "note.text" : "square.and.pencil")
        }
        .badge(pageNoteCount)
        .help("Notes for this page (⇧⌘N)")
        .popover(isPresented: $showNotesPopover, arrowEdge: .bottom) {
            AlbumPageNotesPanel(album: album, pageIndex: currentPage,
                           lessonTitle: currentLesson?.title ?? album.title)
        }
    }

    private var relatedButton: some View {
        Button {
            showRelatedPopover = true
        } label: {
            Label("Related Lessons", systemImage: "arrow.triangle.branch")
        }
        .help("Lessons related to this one, across all albums")
        .popover(isPresented: $showRelatedPopover, arrowEdge: .bottom) {
            RelatedLessonsPanel(album: album, currentPage: currentPage) { target in
                showRelatedPopover = false
                openRelated(target)
            }
        }
    }

    private var notebookLessonButton: some View {
        Button {
            showNotebookLessonPopover = true
        } label: {
            Label("Notebook Lesson", systemImage: "book.closed")
        }
        .help("Your own write-up for the lesson on this page")
        .popover(isPresented: $showNotebookLessonPopover, arrowEdge: .bottom) {
            LinkedNotebookLessonsPanel(album: album, currentPage: currentPage) {
                showNotebookLessonPopover = false
            }
        }
    }

    private var summarizeButton: some View {
        Button {
            summarizeCurrentLesson()
        } label: {
            Label("Summarize Lesson", systemImage: "sparkles")
        }
        .disabled(!intelligence.isAvailable || !library.indexReady)
        .help(intelligence.isAvailable
              ? "Summarize this lesson with Apple Intelligence"
              : (intelligence.unavailableExplanation ?? "Unavailable"))
    }

    // MARK: State helpers

    private var isBookmarked: Bool {
        bookmarks.contains { Int($0.pageIndex) == currentPage }
    }

    private var pageNoteCount: Int {
        notes.count { Int($0.pageIndex) == currentPage }
    }

    private func toggleBookmark() {
        AlbumUserDataStore.toggleBookmark(albumID: album.id, pageIndex: currentPage,
                                lessonTitle: currentLesson?.title ?? album.title,
                                in: context)
    }

    private func goTo(pageIndex: Int, highlight: String? = nil) {
        jump = AlbumPageJump(id: UUID(), pageIndex: pageIndex, highlight: highlight)
        currentPage = pageIndex
    }

    private func consumeTarget() {
        guard let target = nav.pageTarget, target.albumID == album.id else { return }
        nav.pageTarget = nil
        didRestorePosition = true
        goTo(pageIndex: target.pageIndex, highlight: target.highlight)
    }

    /// Coalesces page turns into one write. Paging through a lesson is a
    /// burst of `currentPage` changes; only where the guide settles matters.
    private func schedulePositionSave() {
        positionSaveTask?.cancel()
        let pageIndex = currentPage
        positionSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            persistPosition(pageIndex: pageIndex)
        }
    }

    /// Writes the reading position, and a recent visit when the guide has
    /// moved into a different lesson than the one last recorded.
    private func persistPosition(pageIndex: Int) {
        if let lesson = album.lesson(forPage: pageIndex), lesson.title != lastRecordedLessonTitle {
            lastRecordedLessonTitle = lesson.title
            AlbumUserDataStore.recordVisit(albumID: album.id, pageIndex: pageIndex,
                                           lessonTitle: lesson.title, in: context)
        }
        AlbumUserDataStore.saveReadingPosition(albumID: album.id, pageIndex: pageIndex, in: context)
    }

    /// Reopen the album to where the user left off (on any of their devices).
    private func restorePositionIfNeeded() {
        guard !didRestorePosition else { return }
        didRestorePosition = true
        if let saved = AlbumUserDataStore.readingPosition(albumID: album.id, in: context),
           saved > 0, saved < album.pageCount {
            goTo(pageIndex: saved)
        }
    }

    private func openRelated(_ target: (albumID: String, pageIndex: Int)) {
        if target.albumID == album.id {
            goTo(pageIndex: target.pageIndex)
        } else if nav.isAlbumWindow {
            openWindow(id: "AlbumWindow", value: "\(target.albumID)#\(target.pageIndex + 1)")
        } else {
            nav.jump(albumID: target.albumID, pageIndex: target.pageIndex)
        }
    }

    // MARK: Highlights

    private func highlightCurrentSelection() {
        guard let selection = proxy.currentSelection,
              let text = selection.string?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return }
        for page in selection.pages {
            let pageIndex = album.document.index(for: page)
            let rects = selection.selectionsByLine()
                .filter { $0.pages.contains(page) }
                .map { $0.bounds(for: page) }
                .filter { !$0.isEmpty }
            guard !rects.isEmpty else { continue }
            let lesson = album.lesson(forPage: pageIndex)
            AlbumUserDataStore.addHighlight(albumID: album.id, pageIndex: pageIndex,
                                            lessonTitle: lesson?.title ?? album.title,
                                            text: String(text.prefix(300)), rects: rects,
                                            in: context)
        }
        proxy.clearSelection()
        album.applyHighlights(albumHighlights)
    }

    // MARK: Ink

    private func loadInk() {
        #if os(iOS)
        var drawings: [Int: PKDrawing] = [:]
        for item in AlbumUserDataStore.ink(albumID: album.id, in: context) {
            if let data = item.drawingData, let drawing = try? PKDrawing(data: data) {
                drawings[Int(item.pageIndex)] = drawing
            }
        }
        ink.drawings = drawings
        ink.onSave = { pageIndex, drawing in
            scheduleInkSave(pageIndex: pageIndex, drawing: drawing)
        }
        #endif
    }

    #if os(iOS)
    private func scheduleInkSave(pageIndex: Int, drawing: PKDrawing) {
        inkSaveTask?.cancel()
        let albumID = album.id
        inkSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            let data = drawing.strokes.isEmpty ? Data() : drawing.dataRepresentation()
            AlbumUserDataStore.saveInk(albumID: albumID, pageIndex: pageIndex,
                             drawingData: data, in: context)
        }
    }
    #endif

    // MARK: Export

    private var exportFilename: String {
        let lesson = currentLesson?.title ?? "Lesson"
        return "\(album.title) – \(lesson)"
    }

    private func exportCurrentLesson() {
        let range = album.lessonRange(forPage: currentPage)
        let exported = PDFDocument()
        var inserted = 0
        for pageIndex in range {
            if let page = album.document.page(at: pageIndex),
               let copy = page.copy() as? PDFPage {
                exported.insert(copy, at: inserted)
                inserted += 1
            }
        }
        guard inserted > 0, let data = exported.dataRepresentation() else { return }
        exportDocument = PDFExportDocument(data: data)
        showExporter = true
    }

    // MARK: Summaries

    private func summarizeCurrentLesson() {
        guard let lesson = currentLesson else { return }
        let range = album.lessonRange(forPage: currentPage)
        let text = range.compactMap { library.text(albumID: album.id, pageIndex: $0) }
            .joined(separator: "\n")
        let state = AlbumSummaryState(lesson: lesson)
        // Presenting from the button action lands inside AppKit's toolbar layout
        // pass; hop to the next main-actor turn so the bar finishes measuring first.
        Task { @MainActor in
            summary = state
            do {
                state.result = try await intelligence.summarize(
                    lessonTitle: lesson.title, albumTitle: album.title, text: text)
            } catch {
                state.error = "Couldn't summarize: \(error.localizedDescription)"
            }
        }
    }

}

// MARK: - Export document

nonisolated struct PDFExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.pdf]

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - Related lessons

struct RelatedLessonsPanel: View {
    @Environment(AlbumLibrary.self) private var library
    let album: Album
    let currentPage: Int
    let onSelect: ((albumID: String, pageIndex: Int)) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Related Lessons", systemImage: "arrow.triangle.branch")
                .font(.headline)
            switch library.semantic.status {
            case .ready:
                let matches = relatedMatches
                if matches.isEmpty {
                    Text("No related lessons found.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(matches) { match in
                        if let target = library.album(id: match.albumID),
                           target.lessons.indices.contains(match.lessonIndex) {
                            let lesson = target.lessons[match.lessonIndex]
                            Button {
                                onSelect((match.albumID, lesson.pageIndex))
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: target.subject.symbol)
                                        .foregroundStyle(target.subject.color)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(lesson.title)
                                            .font(.callout.weight(.medium))
                                            .multilineTextAlignment(.leading)
                                        Text("\(target.title) · p. \(lesson.pageIndex + 1)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            case .building, .idle:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Preparing the lesson map…")
                        .foregroundStyle(.secondary)
                }
            case .unavailable:
                Text("Semantic lesson matching isn't available on this device.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 340, alignment: .leading)
    }

    private var relatedMatches: [AlbumSemanticIndex.Match] {
        guard let lesson = album.lesson(forPage: currentPage),
              let index = album.lessons.lastIndex(where: {
                  $0.pageIndex == lesson.pageIndex && $0.title == lesson.title
              }) else { return [] }
        return library.semantic.related(albumID: album.id, lessonIndex: index, limit: 5)
    }
}

// MARK: - Outline list

struct AlbumOutlineListView: View {
    @Environment(\.openWindow) private var openWindow
    let album: Album
    let currentPage: Int
    let onSelect: (AlbumOutlineNode) -> Void

    @State private var filter = ""
    @State private var selection: String?

    private var nodesByID: [String: AlbumOutlineNode] {
        var out: [String: AlbumOutlineNode] = [:]
        func walk(_ nodes: [AlbumOutlineNode]) {
            for node in nodes {
                out[node.id] = node
                if let children = node.children { walk(children) }
            }
        }
        walk(album.outline)
        return out
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Filter contents", text: $filter)
                .textFieldStyle(.roundedBorder)
                .padding(10)
            Divider()
            List(selection: $selection) {
                if filter.trimmingCharacters(in: .whitespaces).isEmpty {
                    OutlineGroup(album.outline, children: \.children) { node in
                        row(for: node)
                    }
                } else {
                    ForEach(filteredNodes) { node in
                        row(for: node)
                    }
                }
            }
            .listStyle(.sidebar)
            .onChange(of: selection) {
                if let selection, let node = nodesByID[selection] {
                    onSelect(node)
                }
            }
        }
    }

    private var filteredNodes: [AlbumOutlineNode] {
        let needle = AlbumLibrary.fold(filter)
        var out: [AlbumOutlineNode] = []
        func walk(_ nodes: [AlbumOutlineNode]) {
            for node in nodes {
                if AlbumLibrary.fold(node.title).contains(needle) {
                    out.append(AlbumOutlineNode(id: node.id, title: node.title,
                                           pageIndex: node.pageIndex, children: nil))
                }
                if let children = node.children { walk(children) }
            }
        }
        walk(album.outline)
        return out
    }

    private func row(for node: AlbumOutlineNode) -> some View {
        let isCurrent = album.lesson(forPage: currentPage)
            .map { $0.pageIndex == node.pageIndex && $0.title == node.title } ?? false
        return HStack {
            Text(node.title)
                .lineLimit(2)
                .fontWeight(isCurrent ? .semibold : .regular)
            Spacer(minLength: 6)
            Text("\(node.pageIndex + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
        .tag(node.id)
        .contextMenu {
            Button("Open in New Window") {
                openWindow(id: "AlbumWindow", value: "\(album.id)#\(node.pageIndex + 1)")
            }
        }
    }
}

// MARK: - Per-page notes panel

struct AlbumPageNotesPanel: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [
        NSSortDescriptor(keyPath: \CDAlbumPageNote.createdAt, ascending: true)
    ])
    private var allNotes: FetchedResults<CDAlbumPageNote>
    let album: Album
    let pageIndex: Int
    let lessonTitle: String

    @State private var draft = ""

    private var pageNotes: [CDAlbumPageNote] {
        allNotes.filter { $0.albumID == album.id && Int($0.pageIndex) == pageIndex }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("\(lessonTitle) — p. \(pageIndex + 1)", systemImage: "note.text")
                .font(.headline)
                .lineLimit(1)
            if !pageNotes.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(pageNotes) { note in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(note.text)
                                    .font(.callout)
                                    .textSelection(.enabled)
                                HStack {
                                    Text(note.createdAt ?? Date(), style: .date)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Button(role: .destructive) {
                                        context.delete(note)
                                        context.safeSave()
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.caption)
                                    }
                                    .buttonStyle(.plain)
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(album.subject.color.opacity(0.08),
                                        in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .frame(maxHeight: 220)
            }
            TextField("Add a note for this page…", text: $draft, axis: .vertical)
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)
                .onSubmit(saveDraft)
            HStack {
                Spacer()
                Button("Save Note", action: saveDraft)
                    .buttonStyle(.borderedProminent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func saveDraft() {
        AlbumUserDataStore.addNote(albumID: album.id, pageIndex: pageIndex,
                         lessonTitle: lessonTitle, text: draft, in: context)
        draft = ""
    }
}

// MARK: - Lesson summary sheet

@Observable
final class AlbumSummaryState: Identifiable {
    let id = UUID()
    let lesson: AlbumLessonRef
    var result: String?
    var error: String?

    init(lesson: AlbumLessonRef) { self.lesson = lesson }
}

struct AlbumSummarySheet: View {
    @Environment(\.dismiss) private var dismiss
    let state: AlbumSummaryState
    let album: Album
    let saveAsNote: (String, AlbumLessonRef) -> Void
    @State private var saved = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(state.lesson.title, systemImage: "sparkles")
                .font(.title3.bold())
            Divider()
            Group {
                if let error = state.error {
                    Text(error).foregroundStyle(.red)
                } else if let result = state.result {
                    ScrollView {
                        Text(markdown(result))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Summarizing on device…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 200)
            Divider()
            HStack {
                Text("Generated on device by Apple Intelligence — double-check against the album.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                if let result = state.result {
                    Button(saved ? "Saved" : "Save as Note") {
                        saveAsNote(result, state.lesson)
                        saved = true
                    }
                    .disabled(saved)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460, idealWidth: 520, minHeight: 380)
    }

    private func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(s)
    }
}
