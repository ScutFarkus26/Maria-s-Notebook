// PDFThumbnailView.swift
// PDF thumbnail components extracted from StudentFilesTab

import SwiftUI
import CoreData
@preconcurrency import PDFKit
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

struct PDFThumbnail: View {
    let data: Data?

    @State private var page: PDFPage?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let page {
                PDFThumbnailView(page: page)
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
            await loadPDFPage()
        }
    }

    private func loadPDFPage() async {
        guard let pdfData = data else {
            isLoading = false
            return
        }

        // Keep PDFKit objects on the current actor to avoid crossing non-Sendable types.
        let pdfDocument = PDFDocument(data: pdfData)
        self.page = pdfDocument?.page(at: 0)
        self.isLoading = false
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
                Task { @MainActor in
                    nsView.document = existingDocument
                    nsView.go(to: targetPage)
                }
            } else if nsView.currentPage !== page {
                Task { @MainActor in
                    nsView.go(to: targetPage)
                }
            }
        } else if nsView.document == nil {
            // Only create a new document if the page doesn't have one and view has no document
            Task { @MainActor in
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
