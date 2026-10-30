import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Reports in a meeting (2026-10-30): they have their own section, and a
// stage set on the card is its decision, with Presented's close kept as a
// receipt so a later choice takes it back on every copy.
extension MeetingDraftStoreTests {

    @MainActor
    private func seedReport(
        for child: UUID, with partner: UUID, in context: NSManagedObjectContext
    ) throws -> [CDWorkModel] {
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Research Report", area: "Language")
        let copies = try ReportStages.startReport(
            title: "Squishies", studentIDs: [child, partner], lessonID: try #require(lesson.id), context: context
        )
        #expect(CoreDataTestHelpers.save(context))
        return copies
    }

    @Test("A report is listed under Reports, never as stuck or open work")
    @MainActor
    func reportsHaveTheirOwnList() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        let report = try seedReport(for: child, with: UUID(), in: context)[0]
        report.createdAt = AppCalendar.addingDays(-60, to: Date())
        let practice = CoreDataTestHelpers.seedWorkModel(in: context, title: "Stamp Game", studentID: child)
        practice.createdAt = AppCalendar.addingDays(-60, to: Date())

        let split = MeetingWorkSnapshotHelper.sessionWork([report, practice], workOverdueDays: 14, reviewed: [])
        #expect(split.reports == [report])
        #expect(split.stuck == [practice])
        #expect(split.open.isEmpty)
    }

    @Test("A stage set on the card is its decision and moves every copy")
    @MainActor
    func stageFromTheCardIsTheDecision() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        defer { MeetingPersistenceService.clearCurrent(studentID: child) }
        let copies = try seedReport(for: child, with: UUID(), in: context)
        let reportID = try #require(copies[0].id)

        let draft = MeetingDraftModel(studentID: child)
        draft.load(context: context)
        #expect(draft.setStage(2, of: copies[0], context: context))

        #expect(draft.reviewedWorkIDs == [reportID])
        #expect(copies.allSatisfy { ReportStages.currentStage(of: $0) == 2 })
        #expect(copies.allSatisfy { $0.status == .active })
        #expect(MeetingPersistenceService.loadCurrent(studentID: child).reviewedWorkIDs == [reportID.uuidString])
    }

    @Test("Presented closes every copy, and a later stage takes the close back")
    @MainActor
    func presentedInAMeetingIsTakenBack() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        defer { MeetingPersistenceService.clearCurrent(studentID: child) }
        let copies = try seedReport(for: child, with: UUID(), in: context)
        let reportID = try #require(copies[0].id)

        let draft = MeetingDraftModel(studentID: child)
        draft.load(context: context)
        #expect(draft.setStage(4, of: copies[0], context: context))
        #expect(copies.allSatisfy { $0.status == .done })
        #expect(draft.closeTokens[reportID]?.count == 1)

        #expect(draft.setStage(3, of: copies[0], context: context))
        #expect(copies.allSatisfy { $0.status == .active })
        #expect(copies.allSatisfy { $0.completedAt == nil })
        #expect(copies.allSatisfy { ReportStages.currentStage(of: $0) == 3 })
        #expect(draft.closeTokens[reportID] == nil)
    }

    @Test("Rest after Presented reopens the report and rests her copy")
    @MainActor
    func restAfterPresentedReopens() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        defer { MeetingPersistenceService.clearCurrent(studentID: child) }
        let copies = try seedReport(for: child, with: UUID(), in: context)

        let draft = MeetingDraftModel(studentID: child)
        draft.load(context: context)
        #expect(draft.setStage(4, of: copies[0], context: context))
        draft.rest(copies[0], until: AppCalendar.addingDays(10, to: Date()), context: context)

        #expect(copies.allSatisfy { $0.status.isOpen })
        #expect(copies[0].isResting)
    }
}
