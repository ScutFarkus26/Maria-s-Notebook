import SwiftUI
#if os(macOS)
import AppKit
#endif

enum PdfRenderer {
    #if os(macOS)
    static func render(view: AnyView, suggestedFileName: String = "Report.pdf") throws {
        let panel = NSSavePanel()
        panel.allowedFileTypes = ["pdf"]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = suggestedFileName.hasSuffix(".pdf") ? suggestedFileName : suggestedFileName + ".pdf"
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 612, height: 792) // Letter size at 72 DPI
        let data = hosting.dataWithPDF(inside: hosting.bounds)
        try data.write(to: url)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
    #endif
}
