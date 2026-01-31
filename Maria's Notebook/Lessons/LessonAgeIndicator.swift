import Foundation
import SwiftUI
import SwiftData

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

/// Helper to compute school-day age counts using the app's SchoolCalendar.
struct LessonAgeHelper {
    /// Synchronous helper that determines if a date is a non-school day using direct ModelContext fetches.
    /// Rules:
    /// - Explicit NonSchoolDay records mark weekdays as non-school
    /// - Weekends are non-school by default unless a SchoolDayOverride exists for that date
    private static func isNonSchoolDaySync(_ date: Date, using context: ModelContext, calendar: Calendar) -> Bool {
        let day = calendar.startOfDay(for: date)

        // 1) Explicit non-school day wins
        do {
            let nsDescriptor = FetchDescriptor<NonSchoolDay>(predicate: #Predicate { $0.date == day })
            let nonSchoolDays: [NonSchoolDay] = try context.fetch(nsDescriptor)
            if !nonSchoolDays.isEmpty { return true }
        } catch {
            // On fetch error, fall back to weekend logic below
        }

        // 2) Weekends are non-school by default (Sunday=1, Saturday=7)
        let weekday = calendar.component(.weekday, from: day)
        let isWeekend = (weekday == 1 || weekday == 7)
        guard isWeekend else { return false }

        // 3) Weekend override makes it a school day
        do {
            let ovDescriptor = FetchDescriptor<SchoolDayOverride>(predicate: #Predicate { $0.date == day })
            let overrides: [SchoolDayOverride] = try context.fetch(ovDescriptor)
            if !overrides.isEmpty { return false }
        } catch {
            // If override fetch fails, assume weekend remains non-school
        }
        return true
    }

    /// Compute the number of school days between `createdAt` (start of day) and `today` (start of day),
    /// counting only days that are not marked as non-school by SchoolCalendar.
    /// Returns 0 when `today` is the same start-of-day as `createdAt` or earlier.
    static func schoolDaysSinceCreation(createdAt: Date, asOf today: Date = Date(), using context: ModelContext, calendar: Calendar = .current) -> Int {
        let start = calendar.startOfDay(for: createdAt)
        let end = calendar.startOfDay(for: today)
        if end <= start { return 0 }
        var count = 0
        var cursor = start
        while cursor < end {
            if !isNonSchoolDaySync(cursor, using: context, calendar: calendar) {
                count += 1
            }
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return max(0, count)
    }
}

extension StudentLessonSnapshot {
    /// Convenience wrapper to compute school-day age directly from a snapshot.
    func schoolDaysSinceCreation(asOf today: Date = Date(), using context: ModelContext, calendar: Calendar = .current) -> Int {
        return LessonAgeHelper.schoolDaysSinceCreation(createdAt: self.createdAt, asOf: today, using: context, calendar: calendar)
    }
}
