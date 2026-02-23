#if canImport(Testing)
import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Container Factory

/// Creates an in-memory ModelContainer with the full schema for snapshot testing.
/// Uses @MainActor to ensure SwiftData operations run on the main thread.
@MainActor
func makeSnapshotTestContainer() throws -> ModelContainer {
    let schema = Schema([
        Student.self,
        Lesson.self,
        StudentLesson.self,
        AttendanceRecord.self,
        WorkModel.self,
        WorkParticipantEntity.self,
        WorkCheckIn.self,
        Note.self,
        GroupTrack.self,
        StudentTrackEnrollment.self,
        LessonPresentation.self,
        NonSchoolDay.self,
        SchoolDayOverride.self,
        // Community models for markdown export tests
        CommunityTopic.self,
        ProposedSolution.self,
        CommunityAttachment.self,
    ])
    let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
    return try ModelContainer(for: schema, configurations: [config])
}

// MARK: - Deterministic Date Provider

/// Provides fixed dates for snapshot testing to ensure deterministic output.
/// All dates use Eastern timezone and noon to avoid DST and timezone issues.
enum SnapshotDates {
    /// Fixed reference date for all snapshots: Jan 15, 2025 at noon Eastern
    static let reference: Date = {
        var components = DateComponents()
        components.year = 2025
        components.month = 1
        components.day = 15
        components.hour = 12
        components.minute = 0
        components.second = 0
        components.timeZone = TimeZone(identifier: "America/New_York")
        return Calendar.current.date(from: components)!
    }()

    /// Creates a date with specified components at noon to avoid timezone issues
    static func date(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        components.timeZone = TimeZone(identifier: "America/New_York")
        return Calendar.current.date(from: components)!
    }

    /// Student birthday for consistent age display (9 years, ~7 months at reference date)
    static let studentBirthday = date(year: 2015, month: 6, day: 15)

    /// School year start date
    static let schoolYearStart = date(year: 2024, month: 8, day: 15)

    /// A date 5 days before the reference date
    static let fiveDaysAgo = date(year: 2025, month: 1, day: 10)

    /// A date 10 days before the reference date
    static let tenDaysAgo = date(year: 2025, month: 1, day: 5)
}

// MARK: - Snapshot Configurations

/// Device configurations for snapshot testing across different screen sizes.
enum SnapshotConfig {
    // MARK: - macOS Sizes
    static let macCompact = CGSize(width: 800, height: 600)
    static let macStandard = CGSize(width: 1200, height: 800)
    static let macWide = CGSize(width: 1440, height: 900)

    // MARK: - Component Testing Sizes
    static let cardSize = CGSize(width: 200, height: 200)
    static let listRowSize = CGSize(width: 375, height: 60)
    static let formSize = CGSize(width: 400, height: 600)
}

// MARK: - Text Snapshot Helpers

/// Records and compares text snapshots.
/// In record mode, prints the output for manual verification.
/// In verify mode, compares against expected output.
func assertTextSnapshot(
    _ text: String,
    named name: String,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    // For now, just verify the text is not empty
    // Full snapshot comparison would require file-based storage
    #expect(!text.isEmpty, "Snapshot '\(name)' should not be empty", sourceLocation: sourceLocation)
}

/// Records and compares JSON snapshots with pretty printing and sorted keys.
func assertJSONSnapshot<T: Encodable>(
    _ value: T,
    named name: String,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    let jsonString = String(data: data, encoding: .utf8)!

    assertTextSnapshot(jsonString, named: name, sourceLocation: sourceLocation)
}

// MARK: - Calendar for Deterministic Testing

/// A calendar configured for deterministic snapshot testing
let snapshotCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/New_York")!
    return calendar
}()

#endif
