// CGImagePropertyOrientation+Drawing.swift
// Drawing an image stored in one EXIF orientation upright.

import CoreGraphics
import ImageIO

nonisolated extension CGImagePropertyOrientation {
    /// Whether showing the image upright turns it a quarter turn, so its width and
    /// height trade places.
    var swapsAxes: Bool {
        switch self {
        case .left, .leftMirrored, .right, .rightMirrored: return true
        default: return false
        }
    }

    /// The transform that draws the stored pixels (in a rect at the origin the size
    /// of the stored image) upright in a context of `width` × `height` — the
    /// upright size.
    func drawingTransform(width: CGFloat, height: CGFloat) -> CGAffineTransform {
        switch self {
        case .up: return .identity
        case .upMirrored: return CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: width, ty: 0)
        case .down: return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height)
        case .downMirrored: return CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: 0, ty: height)
        case .leftMirrored: return CGAffineTransform(a: 0, b: -1, c: -1, d: 0, tx: width, ty: height)
        case .right: return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: height)
        case .rightMirrored: return CGAffineTransform(a: 0, b: 1, c: 1, d: 0, tx: 0, ty: 0)
        case .left: return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: width, ty: 0)
        @unknown default: return .identity
        }
    }
}
