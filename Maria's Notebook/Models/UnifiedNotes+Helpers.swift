import Foundation
import CoreData

enum LegacyNoteFieldConstants: Sendable {
    nonisolated static let reporter = "legacyField"
    nonisolated static let reporterName = "system"
}

// Legacy SwiftData CDNote extensions and entity extensions removed —
// all Core Data equivalents now live in CDUnifiedNotes+Helpers.swift.
// The type aliases (CDAttendanceRecord = CDAttendanceRecord, etc.) caused "invalid redeclaration"
// conflicts with the Core Data versions.
