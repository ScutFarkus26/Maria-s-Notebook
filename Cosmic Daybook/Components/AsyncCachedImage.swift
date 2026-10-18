import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Image Caching

/// In-memory cache for loaded images
final class ImageCache: @unchecked Sendable {
    /// Byte budget of `shared`: about 32 note photos at their 300-pt display size
    /// (one is ~1 MB decoded). An evicted photo comes back from the JPEG disk cache in
    /// milliseconds with the same pixels. Also emptied under memory pressure
    /// (`AppDependencies.handleMemoryPressure`).
    nonisolated static let totalCostLimit = 32 * 1024 * 1024

    nonisolated(unsafe) static let shared: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        cache.totalCostLimit = ImageCache.totalCostLimit
        // Limit to 100 images max
        cache.countLimit = 100
        return cache
    }()

    /// Estimates the memory cost of an image in bytes
    static func estimatedCost(for image: PlatformImage) -> Int {
        #if os(macOS)
        guard let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return 0
        }
        return cost(of: cgImage)
        #else
        guard let cgImage = image.cgImage else {
            return 0
        }
        return cost(of: cgImage)
        #endif
    }

    /// Bytes held by a decoded bitmap.
    nonisolated static func cost(of cgImage: CGImage) -> Int {
        cgImage.bytesPerRow * cgImage.height
    }
}

struct AsyncCachedImage: View {
    let filename: String
    let targetSize: CGSize?
    
    @State private var image: PlatformImage?
    @State private var isLoading = true
    /// The cache key of the photo in `image`.
    @State private var shownKey: String?

    /// Initializes an AsyncCachedImage with optional target size for downsampling.
    /// - Parameters:
    ///   - filename: The image filename to load
    ///   - targetSize: Optional target size for downsampling. If nil, uses a default thumbnail size (300x300).
    init(filename: String, targetSize: CGSize? = nil) {
        self.filename = filename
        self.targetSize = targetSize
    }
    
    var body: some View {
        Group {
            if let image {
                #if os(macOS)
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                #else
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                #endif
            } else if isLoading {
                ProgressView()
                    .frame(maxWidth: 50, maxHeight: 50)
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            }
        }
        // Keyed by the photo and size, so a note given a new photo shows it
        // straight away; a plain `.task` ran once and kept the old photo until
        // the row was rebuilt.
        .task(id: cacheKey) {
            await loadImage(cacheKey: cacheKey)
        }
    }

    /// The effective target size: the default thumbnail size when none was given.
    private var effectiveSize: CGSize {
        targetSize ?? CGSize(width: 300, height: 300)
    }

    private var cacheKey: String {
        CachedPhotoLoader.cacheKey(filename: filename, pointSize: effectiveSize)
    }

    private func loadImage(cacheKey: String) async {
        // A different photo: don't keep showing the one it replaced.
        if shownKey != cacheKey {
            image = nil
            isLoading = true
        }

        // Memory cache, then disk cache, then the photo; disk and photo are read off the main thread
        let loadedImage = await CachedPhotoLoader.image(
            filename: filename,
            cacheKey: cacheKey,
            pointSize: effectiveSize,
            scale: DisplayScale.current
        )
        guard !Task.isCancelled else { return }
        image = loadedImage
        shownKey = cacheKey
        isLoading = false
    }
}
