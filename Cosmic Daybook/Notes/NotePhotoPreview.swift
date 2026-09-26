// NotePhotoPreview.swift
// The photo previews the note editors show while a note is being written.

import CoreGraphics

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// The small photo previews the note editors show. The sizes are shared by the
/// views that frame them and the code that renders them, so a preview holds the
/// pixels its frame needs rather than the whole decoded photo.
enum NotePhotoPreview {
    /// `UnifiedNoteEditor`'s thumbnail beside Choose Photo (aspect fill).
    static let editorSide: CGFloat = UIConstants.CardSize.studentAvatar * 0.75
    /// Quick Note's attachment chip in the Mac toolbar (aspect fill). On iPhone
    /// and iPad the sheet shows a paperclip instead and keeps a preview this size.
    static let quickNoteSide: CGFloat = 20

    /// `cgImage` as the platform image the preview views draw, at `scale` pixels
    /// per point.
    static func image(_ cgImage: CGImage, scale: CGFloat) -> PlatformImage {
        #if os(macOS)
        let size = CGSize(width: CGFloat(cgImage.width) / scale, height: CGFloat(cgImage.height) / scale)
        return NSImage(cgImage: cgImage, size: size)
        #else
        return UIImage(cgImage: cgImage, scale: scale, orientation: .up)
        #endif
    }
}
