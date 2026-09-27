// DocumentCard.swift
// Standalone document card component extracted from StudentFilesTab

import SwiftUI
import CoreData

struct DocumentCard: View {
    let document: CDDocument
    let onOpen: (URL) -> Void
    let onDelete: () -> Void
    let onRename: () -> Void

    /// The thumbnail's file, resolved once per bookmark value instead of on
    /// every redraw (see `DocumentFileURLMemo`); kept for the card's lifetime.
    @State private var thumbnailFile = DocumentFileURLMemo()

    /// Where the document is now, resolved on every tap as it always was: a
    /// file that has moved or gone since the card was drawn opens, or falls
    /// back to the record's data, exactly as before.
    private var fileURL: URL? {
        StudentDocumentFileStorage.resolveURL(
            bookmark: document.pdfFileBookmark,
            relativePath: document.pdfFileRelativePath
        )
    }

    var body: some View {
        Button(action: openDocument) {
            cardContent
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens document")
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: SFSymbol.Action.trash)
            }

            Button(action: onRename) {
                Label("Rename", systemImage: SFSymbol.Education.pencil)
            }
        }
    }

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            PDFThumbnail(
                url: thumbnailFile.url(
                    bookmark: document.pdfFileBookmark,
                    relativePath: document.pdfFileRelativePath
                ),
                data: document.pdfData,
                recordKey: document.objectID.uriRepresentation().absoluteString
            )
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: 120)
                .frame(alignment: .center)
                .padding(.vertical, 12)

            Text(document.title)
                .font(.subheadline)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(document.category)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(
            UIConstants.CornerRadius.control,
            fill: Color.primary.opacity(UIConstants.OpacityConstants.hint),
            stroke: Color.primary.opacity(UIConstants.OpacityConstants.light),
            style: .continuous
        )
        .contentShape(Rectangle())
    }

    private func openDocument() {
        if let url = fileURL {
            onOpen(url)
        } else if let url = createTemporaryFileURL() {
            onOpen(url)
        }
    }

    private func createTemporaryFileURL() -> URL? {
        guard let pdfData = document.pdfData else {
            return nil
        }

        // Create a temporary file URL
        let tempDir = FileManager.default.temporaryDirectory
        let sanitizedTitle = document.title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
        let filename = sanitizedTitle.isEmpty ? "Document.pdf" : "\(sanitizedTitle).pdf"
        let tempURL = tempDir.appendingPathComponent(filename)

        do {
            // Write PDF data to temporary file
            try pdfData.write(to: tempURL)
            return tempURL
        } catch {
            return nil
        }
    }
}
