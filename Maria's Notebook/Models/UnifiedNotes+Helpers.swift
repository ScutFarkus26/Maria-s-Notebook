import Foundation
import CoreData

enum LegacyNoteFieldConstants: Sendable {
    nonisolated static let reporter = "legacyField"
    nonisolated static let reporterName = "system"
}

// Legacy SwiftData Note extensions and entity extensions removed —
// all Core Data equivalents now live in CDUnifiedNotes+Helpers.swift.
// The type aliases (AttendanceRecord = CDAttendanceRecord, etc.) caused "invalid redeclaration"
// conflicts with the Core Data versions.
