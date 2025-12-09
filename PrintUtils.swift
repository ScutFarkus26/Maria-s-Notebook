import SwiftUI

#if os(macOS)
import AppKit
typealias PlatformImage = NSImage
#elseif os(iOS)
import UIKit
typealias PlatformImage = UIImage
#endif

enum PrintUtils {
    static func renderImage<V: View>(from view: V, preferredSize: CGSize? = nil, scale: CGFloat = 2.0) -> PlatformImage? {
        let renderer = ImageRenderer(content: view)
        
        #if os(macOS)
        if let preferredSize {
            renderer.proposedSize = .init(preferredSize)
        }
        return renderer.nsImage
        #elseif os(iOS)
        if let preferredSize {
            renderer.proposedSize = .init(preferredSize)
        }
        renderer.scale = scale
        return renderer.uiImage
        #else
        return nil
        #endif
    }
    
    #if os(macOS)
    static func printImage(_ image: NSImage, jobTitle: String) {
        let imageView = NSImageView(image: image)
        imageView.frame = .init(origin: .zero, size: image.size)
        let printOperation = NSPrintOperation(view: imageView)
        printOperation.jobTitle = jobTitle
        printOperation.showsPrintPanel = true
        printOperation.run()
    }
    
    static func printView<V: View>(view: V, jobTitle: String, preferredSize: CGSize? = nil) {
        guard let image = renderImage(from: view, preferredSize: preferredSize) else { return }
        printImage(image, jobTitle: jobTitle)
    }
    #endif
}
