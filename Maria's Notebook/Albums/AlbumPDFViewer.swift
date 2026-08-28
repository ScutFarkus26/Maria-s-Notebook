// AlbumPDFViewer.swift
// The PDFKit bridge: AlbumPDFViewer wraps PDFView for SwiftUI with page
// tracking, one-shot jumps, and search highlighting; AlbumPDFViewerProxy gives
// the surrounding view (and menu bar) imperative control (zoom, paging,
// find, printing, selection); InkController owns the PencilKit canvases
// PDFKit lays over each page on iOS; ThumbnailStripView wraps the
// page-thumbnail rail.

import SwiftUI
import PDFKit
#if os(iOS)
import PencilKit
#endif

// MARK: - Proxy

/// Lets the surrounding SwiftUI view (and the menu bar, via focused values)
/// drive the underlying PDFView: zoom, paging, printing, find, selection.
@Observable @MainActor
final class AlbumPDFViewerProxy {
    weak var pdfView: PDFView?
    /// Mirrors whether the PDFView currently has a text selection.
    var hasSelection = false

    func zoomIn() { pdfView?.zoomIn(nil) }
    func zoomOut() { pdfView?.zoomOut(nil) }
    func actualSize() {
        guard let view = pdfView else { return }
        view.scaleFactor = view.scaleFactorForSizeToFit
    }
    func nextPage() {
        guard let view = pdfView, view.canGoToNextPage else { return }
        view.goToNextPage(nil)
    }
    func previousPage() {
        guard let view = pdfView, view.canGoToPreviousPage else { return }
        view.goToPreviousPage(nil)
    }
    func printDocument() {
        #if os(macOS)
        pdfView?.document?
            .printOperation(for: .shared, scalingMode: .pageScaleDownToFit, autoRotate: true)?
            .run()
        #endif
    }

    var currentSelection: PDFSelection? { pdfView?.currentSelection }

    func clearSelection() { pdfView?.clearSelection() }

    // MARK: Find in album

    func findMatches(_ query: String) -> [PDFSelection] {
        guard let doc = pdfView?.document,
              !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }
        return doc.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
    }

    func showMatch(_ match: PDFSelection, among all: [PDFSelection]) {
        guard let view = pdfView else { return }
        for selection in all {
            #if os(macOS)
            selection.color = .systemYellow
            #else
            selection.color = .yellow
            #endif
        }
        view.highlightedSelections = all.isEmpty ? nil : all
        view.setCurrentSelection(match, animate: true)
        view.scrollSelectionToVisible(nil)
    }

    func clearFind() {
        pdfView?.highlightedSelections = nil
        pdfView?.setCurrentSelection(nil, animate: false)
    }
}

// MARK: - Ink (iOS)

#if os(iOS)
/// Owns the PencilKit canvases that PDFKit lays over each page, keyed by
/// page index. Drawings load from and save to the synced store.
@Observable @MainActor
final class InkController: NSObject {
    var markupEnabled = false {
        didSet {
            for canvas in canvases.values {
                canvas.isUserInteractionEnabled = markupEnabled
            }
            updateToolPicker()
        }
    }
    var drawings: [Int: PKDrawing] = [:]
    var onSave: ((Int, PKDrawing) -> Void)?

    fileprivate var canvases: [Int: PKCanvasView] = [:]
    private let toolPicker = PKToolPicker()

    fileprivate func canvas(for pageIndex: Int) -> PKCanvasView {
        if let existing = canvases[pageIndex] { return existing }
        let canvas = PKCanvasView()
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.drawingPolicy = .anyInput
        canvas.tag = pageIndex
        canvas.delegate = self
        canvas.drawing = drawings[pageIndex] ?? PKDrawing()
        canvas.isUserInteractionEnabled = markupEnabled
        canvases[pageIndex] = canvas
        toolPicker.addObserver(canvas)
        return canvas
    }

    private func updateToolPicker() {
        guard let canvas = canvases.values.first(where: { $0.window != nil }) ?? canvases.values.first
        else { return }
        toolPicker.setVisible(markupEnabled, forFirstResponder: canvas)
        if markupEnabled {
            canvas.becomeFirstResponder()
        }
    }
}

extension InkController: PKCanvasViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        let pageIndex = canvasView.tag
        drawings[pageIndex] = canvasView.drawing
        onSave?(pageIndex, canvasView.drawing)
    }
}
#endif

// MARK: - PDF viewer

/// SwiftUI wrapper around PDFKit's PDFView with page tracking,
/// one-shot page jumps, and search-term highlighting.
@MainActor
struct AlbumPDFViewer {
    let document: PDFDocument
    @Binding var currentPageIndex: Int
    var jump: AlbumPageJump?
    var proxy: AlbumPDFViewerProxy?
    #if os(iOS)
    var inkController: InkController?
    #endif

    private func configure(_ view: PDFView, coordinator: Coordinator) {
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.pageBreakMargins = .init(top: 6, left: 0, bottom: 6, right: 0)
        coordinator.pdfView = view
        #if os(iOS)
        if inkController != nil {
            view.pageOverlayViewProvider = coordinator
        }
        #endif
        NotificationCenter.default.addObserver(coordinator,
                                               selector: #selector(Coordinator.pageChanged),
                                               name: .PDFViewPageChanged, object: view)
        NotificationCenter.default.addObserver(coordinator,
                                               selector: #selector(Coordinator.selectionChanged),
                                               name: .PDFViewSelectionChanged, object: view)
    }

    private func apply(_ view: PDFView, coordinator: Coordinator) {
        coordinator.parent = self
        proxy?.pdfView = view
        if view.document !== document {
            view.document = document
            coordinator.lastJumpID = nil
        }
        if let jump, jump.id != coordinator.lastJumpID {
            coordinator.lastJumpID = jump.id
            coordinator.perform(jump)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var parent: AlbumPDFViewer
        var lastJumpID: UUID?
        weak var pdfView: PDFView?

        init(parent: AlbumPDFViewer) { self.parent = parent }

        /// Navigates to the jump's page. PDFView silently drops go(to:) before
        /// its first layout, so retry briefly until the view has real bounds.
        func perform(_ jump: AlbumPageJump, attempt: Int = 0) {
            guard let view = pdfView, let doc = view.document,
                  let page = doc.page(at: jump.pageIndex) else { return }
            if view.bounds.isEmpty && attempt < 40 {
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: .milliseconds(50))
                    self?.perform(jump, attempt: attempt + 1)
                }
                return
            }
            view.go(to: PDFDestination(page: page,
                                       at: CGPoint(x: 0, y: page.bounds(for: .mediaBox).height)))
            applyHighlight(jump.highlight)
        }

        @objc func pageChanged() {
            guard let view = pdfView, let page = view.currentPage, let doc = view.document else { return }
            let index = doc.index(for: page)
            if parent.currentPageIndex != index {
                // Bounce off this notification callback before mutating state
                // SwiftUI may already be reading.
                let binding = parent.$currentPageIndex
                Task { @MainActor in binding.wrappedValue = index }
            }
        }

        @objc func selectionChanged() {
            guard let view = pdfView, let proxy = parent.proxy else { return }
            let has = (view.currentSelection?.string?.isEmpty == false)
            if proxy.hasSelection != has {
                // Same bounce as pageChanged: PDFKit posts this mid-layout
                // (notably when Live Text OCR lands on scanned pages), and the
                // highlight toolbar item reads this flag — mutating it inside
                // AppKit's layout pass trips NSToolbarItemViewer's size assertion.
                Task { @MainActor in proxy.hasSelection = has }
            }
        }

        func applyHighlight(_ query: String?) {
            guard let view = pdfView, let doc = view.document else { return }
            guard let query, !query.trimmingCharacters(in: .whitespaces).isEmpty else {
                view.highlightedSelections = nil
                return
            }
            let selections = doc.findString(query, withOptions: [.caseInsensitive, .diacriticInsensitive])
            for selection in selections {
                #if os(macOS)
                selection.color = .systemYellow
                #else
                selection.color = .yellow
                #endif
            }
            view.highlightedSelections = selections.isEmpty ? nil : selections
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

#if os(macOS)
extension AlbumPDFViewer: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        apply(nsView, coordinator: context.coordinator)
    }
}
#else
extension AlbumPDFViewer: UIViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        configure(view, coordinator: context.coordinator)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        apply(uiView, coordinator: context.coordinator)
    }
}

extension AlbumPDFViewer.Coordinator: PDFPageOverlayViewProvider {
    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        guard let ink = parent.inkController, let doc = view.document else { return nil }
        return ink.canvas(for: doc.index(for: page))
    }
}
#endif

// MARK: - Thumbnail strip

/// PDFKit's page-thumbnail rail, bound to the live PDFView so selection
/// and navigation stay in sync.
@MainActor
struct ThumbnailStripView {
    let proxy: AlbumPDFViewerProxy

    private func configure(_ view: PDFKit.PDFThumbnailView) {
        view.thumbnailSize = CGSize(width: 68, height: 90)
        #if os(iOS)
        view.layoutMode = .horizontal
        #endif
    }

    private func apply(_ view: PDFKit.PDFThumbnailView) {
        if view.pdfView !== proxy.pdfView {
            view.pdfView = proxy.pdfView
        }
    }
}

#if os(macOS)
extension ThumbnailStripView: NSViewRepresentable {
    func makeNSView(context: Context) -> PDFKit.PDFThumbnailView {
        let view = PDFKit.PDFThumbnailView()
        configure(view)
        return view
    }

    func updateNSView(_ nsView: PDFKit.PDFThumbnailView, context: Context) {
        apply(nsView)
    }
}
#else
extension ThumbnailStripView: UIViewRepresentable {
    func makeUIView(context: Context) -> PDFKit.PDFThumbnailView {
        let view = PDFKit.PDFThumbnailView()
        configure(view)
        return view
    }

    func updateUIView(_ uiView: PDFKit.PDFThumbnailView, context: Context) {
        apply(uiView)
    }
}
#endif
