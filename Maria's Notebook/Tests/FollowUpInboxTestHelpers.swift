#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Container Factory for FollowUp Tests

@MainActor
func makeFollowUpContainer() throws -> ModelContainer {
    return try makeTestContainer(for: [
        Student.self,
        Lesson.self,
        StudentLesson.self,
        WorkModel.self,
        WorkCheckIn.self,
        Note.self,
        NonSchoolDay.self,
        SchoolDayOverride.self,
    ])
}

// MARK: - School Day Helpers

/// Calculates a date that is N school days (weekdays) before today
func schoolDaysAgo(_ n: Int) -> Date {
    let today = AppCalendar.startOfDay(Date())
    var count = 0
    var cursor = today
    while count < n {
        cursor = AppCalendar.addingDays(-1, to: cursor)
        let weekday = AppCalendar.shared.component(.weekday, from: cursor)
        if weekday != 1 && weekday != 7 { count += 1 }
    }
    return cursor
}

// MARK: - FollowUpInboxItem Builder

struct FollowUpInboxItemBuilder {
    var id: String = "test:123"
    var underlyingID: UUID = UUID()
    var childID: UUID? = UUID()
    var childName: String = "Test Child"
    var title: String = "Test Lesson"
    var kind: FollowUpInboxItem.Kind = .lessonFollowUp
    var statusText: String = "Due Today"
    var ageDays: Int = 7
    var bucket: FollowUpInboxItem.Bucket = .dueToday

    func build() -> FollowUpInboxItem {
        return FollowUpInboxItem(
            id: id,
            underlyingID: underlyingID,
            childID: childID,
            childName: childName,
            title: title,
            kind: kind,
            statusText: statusText,
            ageDays: ageDays,
            bucket: bucket
        )
    }

    func withBucket(_ bucket: FollowUpInboxItem.Bucket) -> FollowUpInboxItemBuilder {
        var copy = self
        copy.bucket = bucket
        return copy
    }

    func withAge(_ ageDays: Int) -> FollowUpInboxItemBuilder {
        var copy = self
        copy.ageDays = ageDays
        return copy
    }

    func withChildName(_ childName: String) -> FollowUpInboxItemBuilder {
        var copy = self
        copy.childName = childName
        return copy
    }

    func withNoChild() -> FollowUpInboxItemBuilder {
        var copy = self
        copy.childID = nil
        return copy
    }
}

// MARK: - Enum Test Helpers

/// Generic helper to test enum property mappings
func expectEnumProperty<T: Equatable, E>(
    for cases: [(E, T)],
    keyPath: KeyPath<E, T>,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    for (enumCase, expected) in cases {
        #expect(enumCase[keyPath: keyPath] == expected, sourceLocation: sourceLocation)
    }
}

#endif
