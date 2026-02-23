import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Image Caching

/// In-memory cache for loaded images
private class ImageCache {
    static let shared: NSCache<NSString, PlatformImage> = {
        let cache = NSCache<NSString, PlatformImage>()
        // Limit to ~100MB to prevent unbounded memory growth
        cache.totalCostLimit = 100 * 1024 * 1024
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
        return cgImage.bytesPerRow * cgImage.height
        #else
        guard let cgImage = image.cgImage else {
            return 0
        }
        return cgImage.bytesPerRow * cgImage.height
        #endif
    }
}

/// Disk cache for downsampled images to persist across app launches
private enum ImageDiskCache {
    /// Returns the disk cache directory URL, creating it if needed
    nonisolated static var cacheDirectory: URL? {
        guard let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let imageCacheDir = cacheDir.appendingPathComponent("ImageCache", isDirectory: true)

        // Create directory if it doesn't exist
        if !FileManager.default.fileExists(atPath: imageCacheDir.path) {
            do {
                try FileManager.default.createDirectory(at: imageCacheDir, withIntermediateDirectories: true)
            } catch {
                print("⚠️ [\(#function)] Failed to create cache directory: \(error)")
                return nil
            }
        }
        return imageCacheDir
    }

    /// Returns the file URL for a cached image with the given key
    nonisolated static func fileURL(for cacheKey: String) -> URL? {
        guard let cacheDir = cacheDirectory else { return nil }
        // Use a hash of the cache key to avoid filesystem issues with special characters
        let safeFilename = cacheKey.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
        return cacheDir.appendingPathComponent("\(safeFilename).jpg")
    }

    /// Loads an image from disk cache
    nonisolated static func loadImage(for cacheKey: String) -> PlatformImage? {
        guard let fileURL = fileURL(for: cacheKey),
              FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            print("⚠️ [\(#function)] Failed to load image data from cache: \(error)")
            return nil
        }

        #if os(macOS)
        return NSImage(data: data)
        #else
        return UIImage(data: data)
        #endif
    }

    /// Saves an image to disk cache
    nonisolated static func saveImage(_ image: PlatformImage, for cacheKey: String) {
        guard let fileURL = fileURL(for: cacheKey) else { return }

        #if os(macOS)
        guard let tiffData = image.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpegData = bitmapImage.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            return
        }
        #else
        guard let jpegData = image.jpegData(compressionQuality: 0.8) else {
            return
        }
        #endif

        do {
            try jpegData.write(to: fileURL)
        } catch {
            print("⚠️ [\(#function)] Failed to save image to disk cache: \(error)")
        }
    }
}

struct AsyncCachedImage: View {
    let filename: String
    let targetSize: CGSize?
    
    @State private var image: PlatformImage?
    @State private var isLoading = true
    
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
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        // Determine the effective target size (use default thumbnail size if not provided)
        let effectiveSize = targetSize ?? CGSize(width: 300, height: 300)

        // Get display scale
        let scale: CGFloat
        #if os(macOS)
        scale = NSScreen.main?.backingScaleFactor ?? 1.0
        #else
        // Use trait collection via key window to avoid deprecated UIScreen.main
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            scale = window.traitCollection.displayScale
        } else {
            scale = 1.0
        }
        #endif

        // Create cache key that includes size to cache different sizes separately
        let cacheKey = "\(filename)_\(Int(effectiveSize.width))x\(Int(effectiveSize.height))"

        // 1. Check in-memory cache first (fastest)
        if let cached = ImageCache.shared.object(forKey: cacheKey as NSString) {
            self.image = cached
            self.isLoading = false
            return
        }

        // 2. Check disk cache (fast, persists across app launches)
        if let diskCached = ImageDiskCache.loadImage(for: cacheKey) {
            // Store in memory cache for subsequent accesses with estimated cost
            let cost = ImageCache.estimatedCost(for: diskCached)
            ImageCache.shared.setObject(diskCached, forKey: cacheKey as NSString, cost: cost)
            self.image = diskCached
            self.isLoading = false
            return
        }

        // 3. Load from source in background (detached task to avoid blocking main thread)
        let loadedImage = await Task.detached(priority: .userInitiated) {
            // Use downsampling for thumbnails to reduce memory usage
            return PhotoStorageService.loadDownsampledImage(
                filename: filename,
                pointSize: effectiveSize,
                scale: scale
            )
        }.value

        // 4. Update caches and UI
        if let loadedImage {
            // Save to memory cache with estimated cost for proper eviction
            let cost = ImageCache.estimatedCost(for: loadedImage)
            ImageCache.shared.setObject(loadedImage, forKey: cacheKey as NSString, cost: cost)
            // Save to disk cache (fire and forget, runs in background)
            Task.detached(priority: .background) {
                ImageDiskCache.saveImage(loadedImage, for: cacheKey)
            }
            self.image = loadedImage
        }
        self.isLoading = false
    }
}

