// Rasterises Cosmic Daybook's icon layer SVGs (Cosmic Daybook/AppIcon.icon/Assets/*.svg) into
// the flat appiconset PNGs: the three iOS 1024s (light, dark, tinted) and the Mac sizes, all on
// the same cream or indigo gradient icon.json gives the .icon. iOS 26+ and macOS 26+ render the
// .icon itself; these PNGs are what older systems and some tools show. Re-run it after editing
// any layer SVG or icon.json so both sets keep the same art.
// Usage, from the repo root: swift Scripts/render_daybook_icon.swift .
import AppKit
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let layersDir = root.appendingPathComponent("Cosmic Daybook/AppIcon.icon/Assets")
let appIconSet = root.appendingPathComponent("Cosmic Daybook/Assets.xcassets/AppIcon.appiconset")
let side = 1024
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

// Bottom-most first (icon.json lists groups and layers top-first; this is that list reversed).
let layerNames = ["Cover", "Spine", "LeftPage", "RightPage", "Gutter", "Rules", "Glow", "Constellation",
                  "Stars", "Writing", "Grammar", "Clock", "Ribbon", "Tabs"]

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(colorSpace: srgb, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, 1
    ])!
}

func loadSVG(_ name: String) -> NSImage {
    let url = layersDir.appendingPathComponent("\(name).svg")
    guard let image = NSImage(contentsOf: url) else { fatalError("could not load \(url.path)") }
    image.size = NSSize(width: side, height: side)
    return image
}

let layers = layerNames.map(loadSVG)

/// The whole icon, flat, on a top-to-bottom gradient.
func render(top: UInt32, bottom: UInt32) -> CGImage {
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    let gradient = CGGradient(colorsSpace: srgb, colors: [rgb(top), rgb(bottom)] as CFArray, locations: [0, 1])!
    // CG's origin is bottom-left: the top stop sits at y = side.
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: 0, y: 0), options: [])
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let full = NSRect(x: 0, y: 0, width: side, height: side)
    for layer in layers {
        layer.draw(in: full, from: .zero, operation: .sourceOver, fraction: 1)
    }
    NSGraphicsContext.restoreGraphicsState()
    return ctx.makeImage()!
}

/// The tinted appearance: the same drawing with its color taken out, on near-black.
func desaturate(_ image: CGImage) -> CGImage {
    let filter = CIFilter(name: "CIColorControls")!
    filter.setValue(CIImage(cgImage: image), forKey: kCIInputImageKey)
    filter.setValue(0, forKey: kCIInputSaturationKey)
    let context = CIContext(options: [.workingColorSpace: srgb, .outputColorSpace: srgb])
    return context.createCGImage(filter.outputImage!, from: CGRect(x: 0, y: 0, width: side, height: side))!
}

func scaled(_ image: CGImage, to size: Int) -> CGImage {
    if size == side { return image }
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
    return ctx.makeImage()!
}

func write(_ image: CGImage, as file: String) {
    let url = appIconSet.appendingPathComponent(file)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write failed \(url.path)") }
    print("wrote \(file) \(image.width)x\(image.height)")
}

let light = render(top: 0xFFF7E4, bottom: 0xEFDCB6)
let dark = render(top: 0x2C2346, bottom: 0x15101F)
let tinted = desaturate(render(top: 0x202020, bottom: 0x080808))

// iOS: light, dark, tinted.
write(light, as: "Icon-1024.png")
write(dark, as: "Icon-1024 1.png")
write(tinted, as: "Icon-1024 2.png")
// Mac: every size the asset catalog lists, from the light render.
let macFiles: [(String, Int)] = [
    ("Icon-16.png", 16), ("Icon-32 1.png", 32), ("Icon-32.png", 32), ("Icon-64.png", 64),
    ("Icon-128.png", 128), ("Icon-256 1.png", 256), ("Icon-256.png", 256),
    ("Icon-512 1.png", 512), ("Icon-512.png", 512), ("Icon-1024 3.png", 1024)
]
for (file, size) in macFiles {
    write(scaled(light, to: size), as: file)
}
