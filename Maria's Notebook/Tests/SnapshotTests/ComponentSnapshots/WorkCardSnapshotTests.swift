#if canImport(Testing)
import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import Maria_s_Notebook

/// Tests for WorkCard data layer.
/// Note: Full visual snapshot testing requires the SnapshotTesting library.
/// These tests verify the data models are correctly configured for card display.
@Suite("Work Card Data Tests")
struct WorkCardSnapshotTests {

    // MARK: - Work Status Tests

    @Test("Grid card active work")
    @MainActor
    func gridCard_activeWork() throws {
        let container = try makeSnapshotTestContainer()
        let work = SnapshotTestData.makeWork(status: .active)
        container.mainContext.insert(work)
        try container.mainContext.save()

        #expect(work.status == .active)
        #expect(work.completedAt == nil)
    }

    @Test("Grid card needs attention")
    @MainActor
    func gridCard_needsAttention() throws {
        let container = try makeSnapshotTestContainer()
        let work = SnapshotTestData.makeWork(
            status: .active,
            assignedAt: SnapshotDates.tenDaysAgo
        )
        container.mainContext.insert(work)
        try container.mainContext.save()

        #expect(work.status == .active)
        // Older work should trigger needs attention
        #expect(work.assignedAt == SnapshotDates.tenDaysAgo)
    }

    @Test("Grid card completed work")
    @MainActor
    func gridCard_completedWork() throws {
        let container = try makeSnapshotTestContainer()
        let work = SnapshotTestData.makeWork(
            status: .complete,
            completedAt: SnapshotDates.reference
        )
        container.mainContext.insert(work)
        try container.mainContext.save()

        #expect(work.status == .complete)
        #expect(work.completedAt != nil)
    }

    @Test("Grid card review status")
    @MainActor
    func gridCard_reviewStatus() throws {
        let container = try makeSnapshotTestContainer()
        let work = SnapshotTestData.makeWork(status: .review)
        container.mainContext.insert(work)
        try container.mainContext.save()

        #expect(work.status == .review)
    }

    // MARK: - Work Type Tests

    @Test("Work type practice")
    @MainActor
    func workType_practice() throws {
        let container = try makeSnapshotTestContainer()
        let work = SnapshotTestData.makeWork(kind: .practice)
        container.mainContext.insert(work)
        try container.mainContext.save()

        #expect(work.workType == .practice)
    }

    @Test("Work type follow-up")
    @MainActor
    func workType_followUp() throws {
        let container = try makeSnapshotTestContainer()
        let work = SnapshotTestData.makeWork(kind: .followUp)
        container.mainContext.insert(work)
        try container.mainContext.save()

        #expect(work.workType == .followUp)
    }

    @Test("Work type report")
    @MainActor
    func workType_report() throws {
        let container = try makeSnapshotTestContainer()
        let work = SnapshotTestData.makeWork(kind: .report, kind: .report)
        container.mainContext.insert(work)
        try container.mainContext.save()

        #expect(work.workType == .report)
    }

    // MARK: - Work Set Tests

    @Test("Work set creation")
    @MainActor
    func workSet_creation() throws {
        let container = try makeSnapshotTestContainer()
        let workSet = SnapshotTestData.makeWorkSet()

        for work in workSet {
            container.mainContext.insert(work)
        }
        try container.mainContext.save()

        #expect(workSet.count == 3)
        #expect(workSet.contains { $0.workType == .practice })
        #expect(workSet.contains { $0.workType == .followUp })
        #expect(workSet.contains { $0.workType == .report })
    }

    // MARK: - Due Date Tests

    @Test("Work with due date")
    @MainActor
    func work_withDueDate() throws {
        let container = try makeSnapshotTestContainer()
        let dueDate = SnapshotDates.date(year: 2025, month: 1, day: 20)
        let work = SnapshotTestData.makeWork(dueAt: dueDate)
        container.mainContext.insert(work)
        try container.mainContext.save()

        #expect(work.dueAt == dueDate)
    }

    @Test("Work without due date")
    @MainActor
    func work_withoutDueDate() throws {
        let container = try makeSnapshotTestContainer()
        let work = SnapshotTestData.makeWork(dueAt: nil)
        container.mainContext.insert(work)
        try container.mainContext.save()

        #expect(work.dueAt == nil)
    }

    // MARK: - Last Touched Tests

    @Test("Work last touched")
    @MainActor
    func work_lastTouched() throws {
        let container = try makeSnapshotTestContainer()
        let work = SnapshotTestData.makeWork(
            lastTouchedAt: SnapshotDates.fiveDaysAgo
        )
        container.mainContext.insert(work)
        try container.mainContext.save()

        #expect(work.lastTouchedAt == SnapshotDates.fiveDaysAgo)
    }

    // MARK: - All Work Statuses Tests

    @Test("All work statuses exist")
    func allStatuses() {
        let statuses = WorkStatus.allCases
        #expect(statuses.count >= 3)
        #expect(statuses.contains(.active))
        #expect(statuses.contains(.complete))
        #expect(statuses.contains(.review))
    }

    // MARK: - All Work Types Tests

    @Test("All work types exist")
    func allWorkTypes() {
        let types = WorkModel.WorkType.allCases
        #expect(types.count >= 3)
        #expect(types.contains(.practice))
        #expect(types.contains(.followUp))
        #expect(types.contains(.report))
    }
}

#endif
