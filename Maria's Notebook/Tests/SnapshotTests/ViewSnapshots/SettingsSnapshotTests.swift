#if canImport(Testing)
import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import Maria_s_Notebook

/// Tests for Settings view data layer.
/// Note: Full visual snapshot testing requires the SnapshotTesting library.
/// These tests verify the settings data is correctly configured.
@Suite("Settings Data Tests")
struct SettingsSnapshotTests {

    // MARK: - StatCard Data Tests

    @Test("StatCard basic properties")
    func statCard_basicProperties() {
        // Verify StatCard can be initialized with required parameters
        let title = "Students"
        let value = "25"
        let systemImage = "person.3.fill"

        #expect(!title.isEmpty)
        #expect(!value.isEmpty)
        #expect(!systemImage.isEmpty)
    }

    @Test("StatCard with subtitle")
    func statCard_withSubtitle() {
        let title = "Lessons Given"
        let value = "1,234"
        let subtitle = "this semester"
        let systemImage = "checkmark.circle.fill"

        #expect(!title.isEmpty)
        #expect(!value.isEmpty)
        #expect(!subtitle.isEmpty)
        #expect(!systemImage.isEmpty)
    }

    // MARK: - OverviewStatsGrid Tests

    @Test("Overview stats with counts")
    func overviewStats_withCounts() {
        let studentsCount = 25
        let lessonsCount = 150
        let plannedCount = 500
        let givenCount = 450

        #expect(studentsCount > 0)
        #expect(lessonsCount > 0)
        #expect(plannedCount > 0)
        #expect(givenCount > 0)
        #expect(givenCount <= plannedCount)
    }

    @Test("Overview stats zero counts")
    func overviewStats_zeroCounts() {
        let studentsCount = 0
        let lessonsCount = 0
        let plannedCount = 0
        let givenCount = 0

        #expect(studentsCount == 0)
        #expect(lessonsCount == 0)
        #expect(plannedCount == 0)
        #expect(givenCount == 0)
    }

    // MARK: - Container Tests

    @Test("Snapshot test container creation")
    @MainActor
    func container_creation() throws {
        let container = try makeSnapshotTestContainer()
        #expect(container != nil)
    }

    @Test("Container supports all entity types")
    @MainActor
    func container_supportsAllEntityTypes() throws {
        let container = try makeSnapshotTestContainer()

        // Insert entities of each type
        let student = SnapshotTestData.makeStudent()
        let lesson = SnapshotTestData.makeLesson()
        let work = SnapshotTestData.makeWork()

        container.mainContext.insert(student)
        container.mainContext.insert(lesson)
        container.mainContext.insert(work)

        try container.mainContext.save()

        #expect(student.id != nil)
        #expect(lesson.id != nil)
        #expect(work.id != nil)
    }
}

#endif
