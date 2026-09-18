import Foundation
import SwiftUI
import CoreData

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Represents the age state of a planned/scheduled lesson based on school days since creation.
enum LessonAgeStatus {
    case fresh
    case warning
    case overdue
}

/// Defaults for thresholds and colors used by the age indicator.
struct LessonAgeDefaults {
    // Thresholds
    static let warningDays: Int = 6   // Fresh: 0-5, Warning: 6-7, Overdue: 8+
    static let overdueDays: Int = 8

    // Default colors (sRGB hex with alpha)
    // Fresh: subtle neutral/blue appropriate for dark mode
    static let freshColorHex: String = "#5A7DFFFF"   // soft blue
    // Warning: soft amber/orange
    static let warningColorHex: String = "#FFB020FF"
    // Overdue: muted red (not neon)
    static let overdueColorHex: String = "#FF6B6BFF"
}

/// Utilities for converting between Color and hex strings for persistence.
struct ColorUtils {
    /// Parse a hex string (#RRGGBB or #RRGGBBAA) into a SwiftUI Color.
    static func color(from hex: String) -> Color {
        let cleaned = hex.trimmed()
        guard cleaned.hasPrefix("#") else { return fallback }
        let hexString = String(cleaned.dropFirst())
        let scanner = Scanner(string: hexString)
        var hexNumber: UInt64 = 0
        guard scanner.scanHexInt64(&hexNumber) else { return fallback }
        let r, g, b, a: Double
        switch hexString.count {
        case 6: // RRGGBB
            r = Double((hexNumber & 0xFF0000) >> 16) / 255.0
            g = Double((hexNumber & 0x00FF00) >> 8) / 255.0
            b = Double(hexNumber & 0x0000FF) / 255.0
            a = 1.0
        case 8: // RRGGBBAA
            r = Double((hexNumber & 0xFF000000) >> 24) / 255.0
            g = Double((hexNumber & 0x00FF0000) >> 16) / 255.0
            b = Double((hexNumber & 0x0000FF00) >> 8) / 255.0
            a = Double(hexNumber & 0x000000FF) / 255.0
        default:
            return fallback
        }
        return Color(red: r, green: g, blue: b, opacity: a)
    }

    /// Convert a Color to a hex string in the form #RRGGBBAA (sRGB).
    static func hexString(from color: Color) -> String {
        #if os(macOS)
        let ns = NSColor(color)
        guard let conv = ns.usingColorSpace(.sRGB) else { return LessonAgeDefaults.freshColorHex }
        let r = conv.redComponent
        let g = conv.greenComponent
        let b = conv.blueComponent
        let a = conv.alphaComponent
        #else
        let ui = UIColor(color)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return LessonAgeDefaults.freshColorHex }
        #endif
        return String(format: "#%02X%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255), Int(a * 255))
    }

    private static var fallback: Color { Color.gray.opacity(0.6) }
}

/// Helper to compute school-day age counts using the app's SchoolCalendarService.
struct LessonAgeHelper {
    /// Compute the number of school days between `createdAt` (start of day) and `today` (start of day).
    /// Routes through the shared school-day cache to avoid issuing a Core Data fetch per day.
    static func schoolDaysSinceCreation(
        createdAt: Date, asOf today: Date = Date(),
        using context: NSManagedObjectContext
    ) -> Int {
        SchoolCalendarService.shared.schoolDaysSinceCreation(
            createdAt: createdAt, asOf: today, using: context
        )
    }
}

extension LessonAssignmentSnapshot {
    /// Convenience wrapper to compute school-day age directly from a snapshot.
    func schoolDaysSinceCreation(
        asOf today: Date = Date(),
        using context: NSManagedObjectContext
    ) -> Int {
        return LessonAgeHelper.schoolDaysSinceCreation(
            createdAt: self.createdAt, asOf: today, using: context
        )
    }
}
