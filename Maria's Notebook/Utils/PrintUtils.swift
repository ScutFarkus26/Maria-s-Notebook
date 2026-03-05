import SwiftUI

#if os(macOS)
import AppKit
import CoreGraphics
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformImage = UIImage
#endif

/// Utilities for rendering SwiftUI views to images and printing/sharing them.
public enum PrintUtils {
    /// Renders a SwiftUI view into a platform image using ImageRenderer.
    /// - Parameters:
    ///   - view: The SwiftUI view to render.
    ///   - preferredSize: Optional preferred size. Pass width with height 0 (or <= 0) to allow natural height.
    ///   - scale: Rendering scale (iOS only). Defaults to 2.0 for a crisper print/share image.
    /// - Returns: A platform image (NSImage/UIImage) or nil if rendering failed.
    @MainActor public static func renderImage<V: View>(
        from view: V,
        preferredSize: CGSize? = nil,
        scale: CGFloat = 2.0
    ) -> PlatformImage? {
        let renderer = ImageRenderer(content: view)
        if let preferredSize {
            let w: CGFloat? = preferredSize.width > 0 ? preferredSize.width : nil
            let h: CGFloat? = preferredSize.height > 0 ? preferredSize.height : nil
            renderer.proposedSize = ProposedViewSize(width: w, height: h)
        }
        #if os(iOS)
        renderer.scale = scale
        return renderer.uiImage
        #else
        return renderer.nsImage
        #endif
    }

    #if os(macOS)
    /// Presents the system print panel to print an image.
    @MainActor public static func printImage(_ image: NSImage, jobTitle: String) {
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: image.size))
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = image

        let printOp = NSPrintOperation(view: imageView)
        printOp.showsPrintPanel = true
        printOp.showsProgressPanel = true
        printOp.printInfo.jobDisposition = .spool
        printOp.jobTitle = jobTitle
        printOp.printInfo.orientation = .landscape
        printOp.run()
    }

    /// Convenience to render and print a SwiftUI view.
    @MainActor public static func printView<V: View>(view: V, jobTitle: String, preferredSize: CGSize? = nil) {
        if let img = renderImage(from: view, preferredSize: preferredSize) {
            printImage(img, jobTitle: jobTitle)
        }
    }

    /// Exports an image to a single-page PDF and opens it in Preview.
    @MainActor public static func exportImageToPDFAndOpen(_ image: NSImage, jobTitle: String) {
        // Convert NSImage to CGImage for drawing
        var proposedRect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &proposedRect, context: nil, hints: nil) else { return }
        let pageRect = CGRect(origin: .zero, size: image.size)

        // Create destination URL in temporary directory
        let sanitized = jobTitle.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ")
        let filename = sanitized.isEmpty ? "Document.pdf" : "\(sanitized).pdf"
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)

        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: nil, nil) else { return }
        ctx.beginPDFPage([kCGPDFContextMediaBox as String: pageRect] as CFDictionary)
        ctx.draw(cg, in: pageRect)
        ctx.endPDFPage()
        ctx.closePDF()

        NSWorkspace.shared.open(url)
    }
    #endif
}
