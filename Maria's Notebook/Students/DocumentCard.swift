// DocumentCard.swift
// Standalone document card component extracted from StudentFilesTab

import SwiftUI
import CoreData

struct DocumentCard: View {
    let document: Document
    let onOpen: (URL) -> Void
    let onDelete: () -> Void
    let onRename: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PDFThumbnail(data: document.pdfData)
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
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.hint))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(UIConstants.OpacityConstants.light))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let url = createTemporaryFileURL() {
                onOpen(url)
            }
        }
        .contextMenu {
            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: SFSymbol.Action.trash)
            }

            Button(action: onRename) {
                Label("Rename", systemImage: SFSymbol.Education.pencil)
            }
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
