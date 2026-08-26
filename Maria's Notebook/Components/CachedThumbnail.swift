// CachedThumbnail.swift
// Decode-once accessor for Core Data thumbnail blobs shown in scrolling grids.

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Decodes a stored thumbnail blob at most once per (record, blob) pair.
///
/// The card views that show these live inside `LazyVGrid`s, and each of them
/// called `PlatformImage(data:)` straight from its `body`. SwiftUI re-evaluates
/// `body` on every scroll pass, selection change, and Core Data merge — which on
/// this app means every CloudKit sync tick — so each visible card was re-running
/// a full JPEG/PNG decode and allocating a fresh bitmap that the previous pass had
/// just thrown away. Routing through the shared `ImageCache` turns that into a
/// dictionary lookup and lets decoded bitmaps be evicted under memory pressure
/// (`AppDependencies.handleMemoryPressure` already clears this cache).
enum CachedThumbnail {

    /// - Parameters:
    ///   - data: The stored blob, typically a Core Data binary attribute.
    ///   - cacheKey: A key that is stable for the record across body passes —
    ///     `objectID.uriRepresentation().absoluteString` is the usual choice.
    ///     The blob's byte count is mixed in, so regenerating a thumbnail
    ///     produces a different key rather than serving a stale bitmap.
    static func image(from data: Data?, cacheKey: String) -> PlatformImage? {
        guard let data, !data.isEmpty else { return nil }
        let key = "\(cacheKey)#\(data.count)" as NSString
        if let cached = ImageCache.shared.object(forKey: key) { return cached }
        guard let image = PlatformImage(data: data) else { return nil }
        ImageCache.shared.setObject(image, forKey: key, cost: ImageCache.estimatedCost(for: image))
        return image
    }
}

extension Image {
    /// Platform-appropriate initializer, so call sites don't each repeat the
    /// `#if os(macOS)` pair around `Image(nsImage:)` / `Image(uiImage:)`.
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}
