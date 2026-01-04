import SwiftUI

// Simple in-memory cache
private class ImageCache {
    static let shared = NSCache<NSString, PlatformImage>()
}

struct AsyncCachedImage: View {
    let filename: String
    @State private var image: PlatformImage?
    @State private var isLoading = true
    
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
        // 1. Check Cache
        if let cached = ImageCache.shared.object(forKey: filename as NSString) {
            self.image = cached
            self.isLoading = false
            return
        }
        
        // 2. Load in background (detached task to avoid blocking main thread)
        let loadedImage = await Task.detached(priority: .userInitiated) {
            return PhotoStorageService.loadImage(filename: filename)
        }.value
        
        // 3. Update UI and Cache
        if let loadedImage {
            ImageCache.shared.setObject(loadedImage, forKey: filename as NSString)
            self.image = loadedImage
        }
        self.isLoading = false
    }
}

