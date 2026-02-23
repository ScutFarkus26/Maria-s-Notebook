#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Duplicate Detection Tests

@Suite("WorkConsolidationService Duplicate Detection Tests", .serialized)
@MainActor
struct WorkConsolidationServiceDuplicateDetectionTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Note.self,
        ])
    }

    @Test("finds duplicates with same title, studentLessonID, and kind")
    func findsDuplicatesWithMatchingCriteria() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentLessonID = UUID()

        let work1 = WorkModel(title: "Math Practice", kind: .practiceLesson, studentLessonID: studentLessonID)
        let work2 = WorkModel(title: "Math Practice", kind: .practiceLesson, studentLessonID: studentLessonID)
        let work3 = WorkModel(title: "Math Practice", kind: .practiceLesson, studentLessonID: studentLessonID)
        context.insert(work1)
        context.insert(work2)
        context.insert(work3)

        let service = WorkConsolidationService(context: context)
        let result = service.consolidateDuplicates()

        #expect(result.groupsConsolidated == 1)
        #expect(result.totalMerged == 2)
        #expect(result.errors.isEmpty)
    }

    @Test("does not consolidate works with different titles")
    func doesNotConsolidateWithDifferentTitles() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentLessonID = UUID()

        let work1 = WorkModel(title: "Math Practice", kind: .practiceLesson, studentLessonID: studentLessonID)
        let work2 = WorkModel(title: "Science Practice", kind: .practiceLesson, studentLessonID: studentLessonID)
        context.insert(work1)
        context.insert(work2)

        let service = WorkConsolidationService(context: context)
        let result = service.consolidateDuplicates()

        #expect(result.groupsConsolidated == 0)
        #expect(result.totalMerged == 0)
    }

    @Test("does not consolidate works with different studentLessonIDs")
    func doesNotConsolidateWithDifferentStudentLessonIDs() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work1 = WorkModel(title: "Math Practice", kind: .practiceLesson, studentLessonID: UUID())
        let work2 = WorkModel(title: "Math Practice", kind: .practiceLesson, studentLessonID: UUID())
        context.insert(work1)
        context.insert(work2)

        let service = WorkConsolidationService(context: context)
        let result = service.consolidateDuplicates()

        #expect(result.groupsConsolidated == 0)
        #expect(result.totalMerged == 0)
    }

    @Test("does not consolidate works with different kinds")
    func doesNotConsolidateWithDifferentWorkTypes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentLessonID = UUID()

        let work1 = WorkModel(title: "Math Practice", kind: .practiceLesson, studentLessonID: studentLessonID)
        let work2 = WorkModel(title: "Math Practice", kind: .research, studentLessonID: studentLessonID)
        context.insert(work1)
        context.insert(work2)

        let service = WorkConsolidationService(context: context)
        let result = service.consolidateDuplicates()

        #expect(result.groupsConsolidated == 0)
        #expect(result.totalMerged == 0)
    }

    @Test("handles no duplicates gracefully")
    func handlesNoDuplicatesGracefully() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work1 = WorkModel(title: "Work A", kind: .practiceLesson)
        let work2 = WorkModel(title: "Work B", kind: .research)
        let work3 = WorkModel(title: "Work C", kind: .followUpAssignment)
        context.insert(work1)
        context.insert(work2)
        context.insert(work3)

        let service = WorkConsolidationService(context: context)
        let result = service.consolidateDuplicates()

        #expect(result.groupsConsolidated == 0)
        #expect(result.totalMerged == 0)
        #expect(result.errors.isEmpty)
    }

    @Test("handles empty database")
    func handlesEmptyDatabase() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let service = WorkConsolidationService(context: context)
        let result = service.consolidateDuplicates()

        #expect(result.groupsConsolidated == 0)
        #expect(result.totalMerged == 0)
        #expect(result.errors.isEmpty)
    }
}

// MARK: - Consolidation Logic Tests

@Suite("WorkConsolidationService Consolidation Logic Tests", .serialized)
@MainActor
struct WorkConsolidationServiceConsolidationLogicTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Note.self,
        ])
    }

    @Test("keeps earliest createdAt as canonical")
    func keepsEarliestCreatedAtAsCanonical() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentLessonID = UUID()
        let oldDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let newDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let work1 = WorkModel(title: "Practice", kind: .practiceLesson, studentLessonID: studentLessonID, createdAt: newDate)
        let work2 = WorkModel(title: "Practice", kind: .practiceLesson, studentLessonID: studentLessonID, createdAt: oldDate)
        context.insert(work1)
        context.insert(work2)

        let service = WorkConsolidationService(context: context)
        _ = service.consolidateDuplicates()

        // Fetch remaining works
        let descriptor = FetchDescriptor<WorkModel>()
        let remaining = try context.fetch(descriptor)

        #expect(remaining.count == 1)
        // The canonical should be the one with the earliest createdAt
        let normalizedOldDate = Calendar.current.startOfDay(for: oldDate)
        #expect(remaining[0].createdAt == normalizedOldDate)
    }

    @Test("deletes duplicate works after consolidation")
    func deletesDuplicatesAfterConsolidation() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentLessonID = UUID()

        for i in 1...5 {
            let work = WorkModel(title: "Duplicate Work", kind: .practiceLesson, studentLessonID: studentLessonID, notes: "Work \(i)")
            context.insert(work)
        }

        let service = WorkConsolidationService(context: context)
        let result = service.consolidateDuplicates()

        #expect(result.groupsConsolidated == 1)
        #expect(result.totalMerged == 4)

        let descriptor = FetchDescriptor<WorkModel>()
        let remaining = try context.fetch(descriptor)

        #expect(remaining.count == 1)
    }

    @Test("returns correct counts for multiple duplicate groups")
    func returnsCorrectCountsForMultipleGroups() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Group 1: 3 duplicates
        let slID1 = UUID()
        for _ in 1...3 {
            let work = WorkModel(title: "Group A", kind: .practiceLesson, studentLessonID: slID1)
            context.insert(work)
        }

        // Group 2: 2 duplicates
        let slID2 = UUID()
        for _ in 1...2 {
            let work = WorkModel(title: "Group B", kind: .research, studentLessonID: slID2)
            context.insert(work)
        }

        // Single work (no duplicates)
        let work = WorkModel(title: "Unique Work", kind: .followUpAssignment)
        context.insert(work)

        let service = WorkConsolidationService(context: context)
        let result = service.consolidateDuplicates()

        #expect(result.groupsConsolidated == 2)  // Two groups had duplicates
        #expect(result.totalMerged == 3)  // 2 merged from Group A + 1 from Group B = 3
        #expect(result.errors.isEmpty)

        let descriptor = FetchDescriptor<WorkModel>()
        let remaining = try context.fetch(descriptor)

        #expect(remaining.count == 3)  // 1 from each duplicate group + 1 unique
    }
}

// MARK: - Merge Behavior Tests

@Suite("WorkConsolidationService Merge Behavior Tests", .serialized)
@MainActor
struct WorkConsolidationServiceMergeBehaviorTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Note.self,
        ])
    }

    @Test("keeps earliest assignedAt")
    func keepsEarliestAssignedAt() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentLessonID = UUID()
        let earlyDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let lateDate = TestCalendar.date(year: 2025, month: 6, day: 15)

        let work1 = WorkModel(title: "Practice", kind: .practiceLesson, studentLessonID: studentLessonID, assignedAt: lateDate)
        let work2 = WorkModel(title: "Practice", kind: .practiceLesson, studentLessonID: studentLessonID, assignedAt: earlyDate)
        context.insert(work1)
        context.insert(work2)

        let service = WorkConsolidationService(context: context)
        _ = service.consolidateDuplicates()

        let descriptor = FetchDescriptor<WorkModel>()
        let remaining = try context.fetch(descriptor)

        #expect(remaining.count == 1)
        #expect(remaining[0].assignedAt == earlyDate)
    }

    @Test("merges notes from duplicates")
    func mergesNotesFromDuplicates() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentLessonID = UUID()

        let work1 = WorkModel(title: "Practice", kind: .practiceLesson, studentLessonID: studentLessonID, notes: "")
        let work2 = WorkModel(title: "Practice", kind: .practiceLesson, studentLessonID: studentLessonID, notes: "Important note from duplicate")
        work2.createdAt = TestCalendar.date(year: 2025, month: 2, day: 1)  // Make work1 canonical (earlier)
        context.insert(work1)
        context.insert(work2)

        let service = WorkConsolidationService(context: context)
        _ = service.consolidateDuplicates()

        let descriptor = FetchDescriptor<WorkModel>()
        let remaining = try context.fetch(descriptor)

        #expect(remaining.count == 1)
        #expect(remaining[0].notes.contains("Important note from duplicate"))
    }

    @Test("preserves completion status if any duplicate is completed")
    func preservesCompletionStatus() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentLessonID = UUID()
        let completionDate = TestCalendar.date(year: 2025, month: 3, day: 1)

        let work1 = WorkModel(title: "Practice", kind: .practiceLesson, studentLessonID: studentLessonID)
        let work2 = WorkModel(title: "Practice", kind: .practiceLesson, studentLessonID: studentLessonID, completedAt: completionDate)
        work2.status = .complete
        // Make work1 canonical
        work2.createdAt = TestCalendar.date(year: 2025, month: 2, day: 1)
        context.insert(work1)
        context.insert(work2)

        let service = WorkConsolidationService(context: context)
        _ = service.consolidateDuplicates()

        let descriptor = FetchDescriptor<WorkModel>()
        let remaining = try context.fetch(descriptor)

        #expect(remaining.count == 1)
        #expect(remaining[0].completedAt != nil)
        #expect(remaining[0].status == .complete)
    }
}

// MARK: - Participant Merging Tests

@Suite("WorkConsolidationService Participant Merging Tests", .serialized)
@MainActor
struct WorkConsolidationServiceParticipantMergingTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Note.self,
        ])
    }

    @Test("merges participants from duplicates")
    func mergesParticipantsFromDuplicates() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentLessonID = UUID()
        let student1 = UUID()
        let student2 = UUID()

        let work1 = WorkModel(title: "Practice", kind: .practiceLesson, studentLessonID: studentLessonID)
        work1.participants = [
            WorkParticipantEntity(studentID: student1, completedAt: nil, work: work1)
        ]

        let work2 = WorkModel(title: "Practice", kind: .practiceLesson, studentLessonID: studentLessonID)
        work2.participants = [
            WorkParticipantEntity(studentID: student2, completedAt: nil, work: work2)
        ]
        work2.createdAt = TestCalendar.date(year: 2025, month: 2, day: 1)

        context.insert(work1)
        context.insert(work2)

        let service = WorkConsolidationService(context: context)
        _ = service.consolidateDuplicates()

        let descriptor = FetchDescriptor<WorkModel>()
        let remaining = try context.fetch(descriptor)

        #expect(remaining.count == 1)
        // Should have both participants
        let participantIDs = Set(remaining[0].participants?.map { $0.studentID } ?? [])
        #expect(participantIDs.count == 2)
        #expect(participantIDs.contains(student1.uuidString))
        #expect(participantIDs.contains(student2.uuidString))
    }

    @Test("uses earliest completion date when merging participants")
    func usesEarliestCompletionDateForParticipants() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentLessonID = UUID()
        let studentID = UUID()
        // Use startOfDay since WorkParticipantEntity normalizes completedAt to start of day
        let earlyDate = TestCalendar.startOfDay(year: 2025, month: 1, day: 15)
        let lateDate = TestCalendar.startOfDay(year: 2025, month: 3, day: 15)

        let work1 = WorkModel(title: "Practice", kind: .practiceLesson, studentLessonID: studentLessonID)
        work1.participants = [
            WorkParticipantEntity(studentID: studentID, completedAt: lateDate, work: work1)
        ]

        let work2 = WorkModel(title: "Practice", kind: .practiceLesson, studentLessonID: studentLessonID)
        work2.participants = [
            WorkParticipantEntity(studentID: studentID, completedAt: earlyDate, work: work2)
        ]
        work2.createdAt = TestCalendar.date(year: 2025, month: 2, day: 1)

        context.insert(work1)
        context.insert(work2)

        let service = WorkConsolidationService(context: context)
        _ = service.consolidateDuplicates()

        let descriptor = FetchDescriptor<WorkModel>()
        let remaining = try context.fetch(descriptor)

        #expect(remaining.count == 1)
        let participant = remaining[0].participants?.first { $0.studentID == studentID.uuidString }
        #expect(participant?.completedAt == earlyDate)
    }
}

// MARK: - Edge Cases Tests

@Suite("WorkConsolidationService Edge Cases Tests", .serialized)
@MainActor
struct WorkConsolidationServiceEdgeCasesTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Note.self,
        ])
    }

    @Test("handles works with nil studentLessonID")
    func handlesNilStudentLessonID() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work1 = WorkModel(title: "Practice", kind: .practiceLesson, studentLessonID: nil)
        let work2 = WorkModel(title: "Practice", kind: .practiceLesson, studentLessonID: nil)
        context.insert(work1)
        context.insert(work2)

        let service = WorkConsolidationService(context: context)
        let result = service.consolidateDuplicates()

        // Should consolidate because both have nil studentLessonID
        #expect(result.groupsConsolidated == 1)
        #expect(result.totalMerged == 1)
    }

    @Test("handles works with empty title")
    func handlesEmptyTitle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentLessonID = UUID()

        let work1 = WorkModel(title: "", kind: .practiceLesson, studentLessonID: studentLessonID)
        let work2 = WorkModel(title: "", kind: .practiceLesson, studentLessonID: studentLessonID)
        context.insert(work1)
        context.insert(work2)

        let service = WorkConsolidationService(context: context)
        let result = service.consolidateDuplicates()

        #expect(result.groupsConsolidated == 1)
        #expect(result.totalMerged == 1)
    }

    @Test("handles works with whitespace-only title")
    func handlesWhitespaceOnlyTitle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentLessonID = UUID()

        let work1 = WorkModel(title: "  ", kind: .practiceLesson, studentLessonID: studentLessonID)
        let work2 = WorkModel(title: "  ", kind: .practiceLesson, studentLessonID: studentLessonID)
        context.insert(work1)
        context.insert(work2)

        let service = WorkConsolidationService(context: context)
        let result = service.consolidateDuplicates()

        // Whitespace is trimmed, so these should be considered duplicates
        #expect(result.groupsConsolidated == 1)
        #expect(result.totalMerged == 1)
    }
}

#endif
