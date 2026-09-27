// BookClubOpenPDFButton.swift
// The packet detail's Open PDF button, which resolves the packet's PDF once
// per stored bookmark instead of on every redraw.

import CoreData
import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Opens the packet's PDF, and is disabled while the PDF can't be found.
///
/// The detail view decided that with `.disabled(resolvedURL() == nil)` in its
/// body, so every redraw resolved the packet's bookmark, and every keystroke
/// in the packet's fields or in its Add fields redraws that view. For a PDF
/// that had gone it also tried the relative path. The button now reads
/// through a `DocumentFileURLMemo`: the first draw resolves exactly as before,
/// and later draws resolve again only when the stored bookmark or path
/// changes. A tap resolves afresh, as it always did.
struct BookClubOpenPDFButton: View {
    @ObservedObject var packet: CDBookClubPacket
    @State private var packetFile = DocumentFileURLMemo()

    var body: some View {
        Button { openPDF() } label: {
            Label("Open PDF", systemImage: "doc.richtext")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(drawnPDF == nil)
    }

    private var drawnPDF: URL? {
        packetFile.url(
            bookmark: packet.packetPDFBookmark,
            relativePath: packet.packetPDFRelativePath,
            resolve: BookClubFileStorage.resolveURL
        )
    }

    private func openPDF() {
        guard let url = BookClubFileStorage.resolveURL(
            bookmark: packet.packetPDFBookmark,
            relativePath: packet.packetPDFRelativePath
        ) else { return }
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }
}
