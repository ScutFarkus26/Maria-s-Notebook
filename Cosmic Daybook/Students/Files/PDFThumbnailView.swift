// PDFThumbnailView.swift
// The Student Files card thumbnail, and the live PDFView page the Resources
// detail sheet shows.

import SwiftUI
import CoreData
@preconcurrency import PDFKit
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// A document card's first page: a thumbnail rendered off the main thread and
/// cached by `StudentFileThumbnailCache`, with a drawn shadow standing in for
/// `PDFView`'s page shadow. Unlike the `PDFView` it replaced, a card keeps no
/// `PDFDocument` or `PDFView` alive.
struct PDFThumbnail: View {
    let url: URL?
    let data: Data?
    /// The record a PDF kept in `data` belongs to (its object URI), which keys its
    /// cached thumbnail.
    let recordKey: String

    init(url: URL? = nil, data: Data? = nil, recordKey: String = "") {
        self.url = url
        self.data = data
        self.recordKey = recordKey
    }

    @State private var thumbnail: StudentFileThumbnailCache.Thumbnail?
    @State private var isLoading = true

    /// `PDFView`'s default page break margins, which it left around the page.
    private static let pageMargins = EdgeInsets(top: 4.75, leading: 4, bottom: 4.75, trailing: 4)

    var body: some View {
        Group {
            if let image = thumbnailImage {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .shadow(color: Color.black.opacity(UIConstants.OpacityConstants.quarter), radius: 2, x: 0, y: 1)
                    .padding(Self.pageMargins)
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: 40, maxHeight: 40)
            } else {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await loadThumbnail()
        }
    }

    /// Decoded once through the shared cache, as the Resources and Stories cards do.
    private var thumbnailImage: PlatformImage? {
        guard let thumbnail else { return nil }
        return CachedThumbnail.image(from: thumbnail.jpegData, cacheKey: thumbnail.key)
    }

    private func loadThumbnail() async {
        thumbnail = await StudentFileThumbnailCache.thumbnail(
            url: url, data: data, recordKey: recordKey, scale: DisplayScale.current
        )
        isLoading = false
    }
}

struct PDFThumbnailView: View {
    let page: PDFPage

    var body: some View {
        #if os(macOS)
        PDFPageViewRepresentable(page: page)
        #else
        PDFPageViewRepresentable(page: page)
        #endif
    }
}

#if os(macOS)
struct PDFPageViewRepresentable: NSViewRepresentable {
    let page: PDFPage

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .clear
        // CDDocument assignment is deferred to updateNSView to avoid layout recursion
        return pdfView
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        // Defer all document/navigation changes to next run loop to avoid layout recursion
        // PDFView internally triggers layout when documents are assigned
        let targetPage = page

        if let existingDocument = page.document {
            if nsView.document !== existingDocument {
                Task {
                    nsView.document = existingDocument
                    nsView.go(to: targetPage)
                }
            } else if nsView.currentPage !== page {
                Task {
                    nsView.go(to: targetPage)
                }
            }
        } else if nsView.document == nil {
            // Only create a new document if the page doesn't have one and view has no document
            Task {
                let newDocument = PDFDocument()
                newDocument.insert(targetPage, at: 0)
                nsView.document = newDocument
            }
        }
    }
}
#else
struct PDFPageViewRepresentable: UIViewRepresentable {
    let page: PDFPage

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()

        // Check if the page already belongs to a document
        if let existingDocument = page.document {
            // Use the existing document to preserve accessibility tag structure
            pdfView.document = existingDocument
            pdfView.go(to: page)
        } else {
            // Only create a new document if the page doesn't have one
            let newDocument = PDFDocument()
            newDocument.insert(page, at: 0)
            pdfView.document = newDocument
        }

        pdfView.autoScales = true
        pdfView.displayMode = .singlePage
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .clear
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // Ensure the view stays in sync with the page
        if let existingDocument = page.document {
            if uiView.document !== existingDocument {
                uiView.document = existingDocument
                uiView.go(to: page)
            } else if uiView.currentPage !== page {
                uiView.go(to: page)
            }
        }
    }
}
#endif
