import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// What the "to check first" lists do with a row (`WorkToShowFirst+Actions`):
/// log it from the present sheet without touching a classmate's part.
@Suite("Work to show first: logging")
@MainActor
struct WorkToShowFirstActionTests {

    private struct Fixture {
        let context: NSManagedObjectContext
        let first: CDLesson
        let second: CDLesson
        let ada: CDStudent
        let ben: CDStudent

        var adaID: UUID { ada.id ?? UUID() }
        var benID: UUID { ben.id ?? UUID() }
        var lessons: [CDLesson] { [first, second] }
    }

    private func fixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeContext()
        let first = CoreDataTestHelpers.seedLesson(
            in: context, name: "Bead Addition", area: "Math", sequence: "Addition"
        )
        first.id = UUID()
        first.orderInSequence = 1
        let second = CoreDataTestHelpers.seedLesson(
            in: context, name: "Stamp Game Addition", area: "Math", sequence: "Addition"
        )
        second.id = UUID()
        second.orderInSequence = 2
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lane")
        ada.id = UUID()
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben", lastName: "Moss")
        ben.id = UUID()
        return Fixture(context: context, first: first, second: second, ada: ada, ben: ben)
    }

    @discardableResult
    private func work(for child: UUID, on lesson: CDLesson, in context: NSManagedObjectContext) throws -> CDWorkModel {
        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: lesson.name, studentID: child, lessonID: try #require(lesson.id)
        )
        work.status = .active
        return work
    }

    /// One row on the first lesson that Ada and Ben share, neither finished.
    private func sharedRow(_ fixture: Fixture) throws -> CDWorkModel {
        let shared = try work(for: fixture.adaID, on: fixture.first, in: fixture.context)
        shared.title = "Bead chains poster"
        for child in [fixture.adaID, fixture.benID] {
            let participant = CDWorkParticipantEntity(context: fixture.context)
            participant.id = UUID()
            participant.studentID = child.uuidString
            participant.work = shared
        }
        return shared
    }

    private func item(for child: UUID, _ fixture: Fixture) throws -> WorkToShowFirst.Item {
        let found = WorkToShowFirst.find(
            lessonID: try #require(fixture.second.id?.uuidString),
            studentIDs: [fixture.adaID, fixture.benID],
            sequences: WorkToShowFirst.Sequences(lessons: fixture.lessons),
            in: fixture.context
        )
        return try #require(found[child]?.first)
    }

    private func scheduledCheckIns(of work: CDWorkModel, in context: NSManagedObjectContext) -> [CDWorkCheckIn] {
        WorkLogService.scheduledCheckIns(of: work, in: context)
    }

    // MARK: - Logging from the present sheet

    @Test("A shared row is never logged from the list, so a classmate's part stays open")
    func sharedRowIsNotLogged() throws {
        let fixture = try fixture()
        let shared = try sharedRow(fixture)
        try fixture.context.save()
        let benItem = try item(for: fixture.benID, fixture)
        #expect(benItem.isHersAlone == false)

        #expect(throws: WorkToShowFirst.LogRefusal.sharedWithOthers) {
            try WorkToShowFirst.log(benItem, as: .done, context: fixture.context, saveCoordinator: nil)
        }
        #expect(shared.status == .active)
        #expect(shared.completedAt == nil)
        let open = QuietStudentsOrder.openStudentIDs(of: shared)
        #expect(open == [fixture.adaID, fixture.benID], "both children's parts still open")
    }

    @Test("Her own row logs, and closes for her alone")
    func ownRowLogs() throws {
        let fixture = try fixture()
        let own = try work(for: fixture.adaID, on: fixture.first, in: fixture.context)
        try fixture.context.save()
        let adaItem = try item(for: fixture.adaID, fixture)
        #expect(adaItem.isHersAlone)

        let receipt = try WorkToShowFirst.log(adaItem, as: .mastered, context: fixture.context, saveCoordinator: nil)

        #expect(receipt.closed == 1)
        #expect(own.status == .mastered)
    }

    @Test("A row logged elsewhere since the list was read is not logged again")
    func loggedElsewhereIsRefused() throws {
        let fixture = try fixture()
        let own = try work(for: fixture.adaID, on: fixture.first, in: fixture.context)
        try fixture.context.save()
        let adaItem = try item(for: fixture.adaID, fixture)
        // Logged in the work sheet while the present sheet still lists it.
        own.status = .done
        try fixture.context.save()
        let records = try fixture.context.count(for: CDFetchRequest(CDWorkCompletionRecord.self))

        #expect(throws: WorkToShowFirst.LogRefusal.noLongerOpen) {
            try WorkToShowFirst.log(adaItem, as: .mastered, context: fixture.context, saveCoordinator: nil)
        }
        #expect(own.status == .done, "the earlier log stands")
        #expect(try fixture.context.count(for: CDFetchRequest(CDWorkCompletionRecord.self)) == records)
    }

    // MARK: - What the lists draw

    @Test("Before you start lists only children on the plan")
    func listsReadOnlyDrawnChildren() throws {
        let fixture = try fixture()
        try work(for: fixture.adaID, on: fixture.first, in: fixture.context)
        try work(for: fixture.benID, on: fixture.first, in: fixture.context)
        let found = WorkToShowFirst.find(
            lessonID: try #require(fixture.second.id?.uuidString),
            studentIDs: [fixture.adaID, fixture.benID],
            sequences: WorkToShowFirst.Sequences(lessons: fixture.lessons),
            in: fixture.context
        )
        #expect(found.count == 2)

        // Ben has come off the plan, but his work is still in the last read.
        let rows = PresentationBeforeYouStartSection.rows(students: [fixture.ada], showFirst: found)
        #expect(rows.map(\.item.studentID) == [fixture.adaID])
        #expect(PresentationBeforeYouStartSection.rows(students: [], showFirst: found).isEmpty)
    }
}
