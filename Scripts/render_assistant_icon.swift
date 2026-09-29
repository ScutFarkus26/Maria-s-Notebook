// Rasterises the Daybook Assistant icon's layer SVGs (Daybook Assistant/AppIcon.icon/
// Assets/Check.svg and Rule.svg) into the three flat 1024x1024 appiconset PNGs (light,
// dark, tinted) that iOS 18–25 show; iOS 26+ renders the .icon itself. Re-run it after
// editing either SVG so both sets keep the same art.
// Usage, from the repo root: swift Scripts/render_assistant_icon.swift .
import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let layers = root.appendingPathComponent("Daybook Assistant/AppIcon.icon/Assets")
let appIconSet = root.appendingPathComponent("Daybook Assistant/Assets.xcassets/AppIcon.appiconset")
let side = 1024
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(colorSpace: srgb, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255, CGFloat(hex & 0xFF) / 255, 1
    ])!
}

func loadSVG(_ name: String) -> NSImage {
    let url = layers.appendingPathComponent("\(name).svg")
    guard let image = NSImage(contentsOf: url) else { fatalError("could not load \(url.path)") }
    image.size = NSSize(width: side, height: side)
    return image
}

/// One layer on a transparent canvas; when `color` is set the layer's alpha becomes a mask for it.
func layerImage(_ svg: NSImage, color: CGColor?) -> CGImage {
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    svg.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    if let color {
        ctx.setBlendMode(.sourceIn)
        ctx.setFillColor(color)
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
    }
    return ctx.makeImage()!
}

struct Variant {
    let file: String
    let top: UInt32
    let bottom: UInt32
    let check: UInt32?   // nil = the SVG's own colour
    let rule: UInt32?
}

let variants = [
    Variant(file: "AppIcon.png", top: 0xFDFBF2, bottom: 0xF0EACD, check: nil, rule: nil),
    Variant(file: "AppIcon-Dark.png", top: 0x2C2346, bottom: 0x151020, check: 0xC9B4D6, rule: nil),
    Variant(file: "AppIcon-Tinted.png", top: 0x000000, bottom: 0x000000, check: 0xFFFFFF, rule: 0xB3B3B3)
]

let check = loadSVG("Check")
let rule = loadSVG("Rule")

for v in variants {
    // Opaque RGB canvas (no alpha channel in the PNG).
    let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let gradient = CGGradient(colorsSpace: srgb, colors: [rgb(v.top), rgb(v.bottom)] as CFArray, locations: [0, 1])!
    // CG's origin is bottom-left: the top stop sits at y = side.
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: side), end: CGPoint(x: 0, y: 0), options: [])
    let full = CGRect(x: 0, y: 0, width: side, height: side)
    // Bottom-most layer first when compositing (icon.json lists them top-first).
    ctx.draw(layerImage(rule, color: v.rule.map(rgb)), in: full)
    ctx.draw(layerImage(check, color: v.check.map(rgb)), in: full)
    let image = ctx.makeImage()!
    let url = appIconSet.appendingPathComponent(v.file)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("write failed \(url.path)") }
    print("wrote \(url.lastPathComponent) \(image.width)x\(image.height) alpha=\(image.alphaInfo.rawValue)")
}
