import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

// Simple in-memory cache
private class ImageCache {
    static let shared = NSCache<NSString, PlatformImage>()
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
        scale = UIScreen.main.scale
        #endif
        
        // Create cache key that includes size to cache different sizes separately
        let cacheKey = "\(filename)_\(Int(effectiveSize.width))x\(Int(effectiveSize.height))"
        
        // 1. Check Cache
        if let cached = ImageCache.shared.object(forKey: cacheKey as NSString) {
            self.image = cached
            self.isLoading = false
            return
        }
        
        // 2. Load in background (detached task to avoid blocking main thread)
        let loadedImage = await Task.detached(priority: .userInitiated) {
            // Use downsampling for thumbnails to reduce memory usage
            return PhotoStorageService.loadDownsampledImage(
                filename: filename,
                pointSize: effectiveSize,
                scale: scale
            )
        }.value
        
        // 3. Update UI and Cache
        if let loadedImage {
            ImageCache.shared.setObject(loadedImage, forKey: cacheKey as NSString)
            self.image = loadedImage
        }
        self.isLoading = false
    }
}

