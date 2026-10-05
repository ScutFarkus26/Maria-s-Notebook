import SwiftUI
import UIKit
import CoreData

/// Restock's colors, light and dark. A level shows in the tile's shape as well
/// as its color (three bars, one, none; Out solid), so color is never the only
/// signal.
enum AssistantRestockStyle {
    /// The Assistant's plum, for the office-run banner, check-offs and choices.
    static let accent = dynamic(light: 0x4A3B6B, dark: 0xB7A6DE)
    /// White text on the accent.
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x1D1730)
    static let accentSoft = dynamic(light: 0xEFEBF7, dark: 0x2E2640)

    struct Level {
        let fill: Color
        let border: Color
        let text: Color
        let detail: Color
        let barOn: Color
        let barOff: Color
        /// Out's bars are outlines on the solid tile.
        let barsOutlined: Bool
    }

    static func level(_ level: RestockLevel) -> Level {
        switch level {
        case .stocked:
            Level(
                fill: Color(.secondarySystemGroupedBackground),
                border: dynamic(light: 0xD6D1E2, dark: 0x3A3546),
                text: .primary,
                detail: .secondary,
                barOn: dynamic(light: 0x48484D, dark: 0xD1D1D6),
                barOff: dynamic(light: 0xE5E5EA, dark: 0x48484A),
                barsOutlined: false
            )
        case .low:
            Level(
                fill: dynamic(light: 0xFFF3E0, dark: 0x3D2A10),
                border: dynamic(light: 0xD98A1C, dark: 0xD98A1C),
                text: dynamic(light: 0x5C2E00, dark: 0xFFDDB0),
                detail: dynamic(light: 0x7A4A12, dark: 0xE8BF8A),
                barOn: dynamic(light: 0xB45309, dark: 0xF0A040),
                barOff: dynamic(light: 0xF1D6AD, dark: 0x5E4422),
                barsOutlined: false
            )
        case .out:
            Level(
                fill: dynamic(light: 0xB4380B, dark: 0xC2410C),
                border: dynamic(light: 0xB4380B, dark: 0xC2410C),
                text: .white,
                detail: Color(white: 1, opacity: 0.85),
                barOn: .white,
                barOff: .white,
                barsOutlined: true
            )
        }
    }

    /// The small Out / Low / One-off tag on an office-run row.
    struct Tag {
        let text: String
        let fill: Color
        let foreground: Color
    }

    /// The tag for a need of `staple` (nil for a one-off). A staple that reads
    /// Stocked while its need is still open (its level and need arrived out
    /// of step from another device, and nothing closes the need on its own)
    /// shows the staple's name: the need is the staple's, not a one-off.
    static func tag(for staple: CDSupply?) -> Tag {
        guard let staple else {
            return Tag(text: "One-off", fill: Color(.tertiarySystemFill), foreground: .primary)
        }
        switch staple.level {
        case .out: return Tag(text: "Out", fill: Self.level(.out).fill, foreground: .white)
        case .low: return Tag(text: "Low", fill: Self.level(.low).fill, foreground: Self.level(.low).text)
        case .stocked: return Tag(text: staple.name, fill: Color(.tertiarySystemFill), foreground: .primary)
        }
    }

    /// Nonisolated, closure and all: SwiftUI resolves a color off the main
    /// thread when it renders asynchronously, and a provider that inherited
    /// the target's main-actor default traps there.
    nonisolated private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { @Sendable traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    nonisolated convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255,
            green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// A level as three bars: three for Stocked, one for Low, none filled for Out.
struct AssistantRestockBars: View {
    let level: RestockLevel
    var barWidth: CGFloat = 13
    var barHeight: CGFloat = 6

    var body: some View {
        let style = AssistantRestockStyle.level(level)
        let filled = switch level {
        case .stocked: 3
        case .low: 1
        case .out: 0
        }
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { index in
                let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
                if style.barsOutlined {
                    shape.strokeBorder(style.barOn.opacity(0.8), lineWidth: 1)
                        .frame(width: barWidth, height: barHeight)
                } else {
                    shape.fill(index < filled ? style.barOn : style.barOff)
                        .frame(width: barWidth, height: barHeight)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
