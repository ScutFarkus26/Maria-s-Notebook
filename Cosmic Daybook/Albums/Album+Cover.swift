// Album+Cover.swift
// An album's library cover: rendered from the first page off the main actor
// and kept as the bitmap PDFKit drew, never as an encoded copy.

import PDFKit
import SwiftUI

extension Album {

    /// Renders the first page for the library grid and hands back the bitmap
    /// PDFKit drew. The cover used to be encoded to TIFF (Mac) or PNG (iOS)
    /// here and decoded again on the main actor, which kept the encoded bytes
    /// beside the pixels for as long as the cover was held.
    nonisolated static func renderCover(url: URL) -> CGImage? {
        guard let doc = PDFDocument(url: url), let page = doc.page(at: 0) else { return nil }
        // A page holds its document weakly, and PDFKit draws nothing for a
        // page whose document is gone: keep it open until the render is done.
        let image = withExtendedLifetime(doc) {
            page.thumbnail(of: CGSize(width: 420, height: 560), for: .mediaBox)
        }
        #if os(macOS)
        // PDFKit draws at the screen's scale; the TIFF held one pixel per
        // point, and a CGImage the image's size in points is those pixels.
        var rect = CGRect(origin: .zero, size: image.size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        #else
        // PDFKit tags the thumbnail DeviceRGB; the PNG it used to become was
        // decoded as sRGB, and that is what the grid showed. Tagging the same
        // pixels sRGB (no copy) keeps it so, and lets the screen draw them as
        // they are: left DeviceRGB, displaying them made a second,
        // colour-matched copy of every cover.
        guard let bitmap = image.cgImage, let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return bitmap.copy(colorSpace: sRGB) ?? bitmap
        #endif
    }

    /// The cover for a rendered bitmap, at the size the decoded TIFF or PNG
    /// had: one point per pixel.
    static func coverImage(from bitmap: CGImage) -> PlatformImage {
        #if os(macOS)
        NSImage(cgImage: bitmap, size: CGSize(width: bitmap.width, height: bitmap.height))
        #else
        UIImage(cgImage: bitmap, scale: 1, orientation: .up)
        #endif
    }

    /// Drops the rendered cover. A library card still on screen asks for it
    /// again: its cover task is keyed on whether the cover is loaded.
    func releaseCover() {
        cover = nil
        coverRequested = false
    }
}
