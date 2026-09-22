import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Logging a work check: one write that sets the status, settles the
/// check-ins, records the completion, files the note, and can be undone.
@Suite("Work log service")
@MainActor
struct WorkLogServiceTests {

    // MARK: - Fixtures

    private struct Room {
        let context: NSManagedObjectContext
        let lessonID = UUID()
        let simma = UUID()
        let naomi = UUID()
        let today = AppCalendar.startOfDay(Date())
        var tomorrow: Date { AppCalendar.addingDays(1, to: today) }
        var nextWeek: Date { AppCalendar.addingDays(7, to: today) }
    }

    private func makeRoom() throws -> Room {
        Room(context: try CoreDataTestHelpers.makeInMemoryStack().viewContext)
    }

    /// One row per child, each naming the other — the shape `assign_work`
    /// and Quick New Work create.
    private func seedLinkedCopies(in room: Room, title: String = "Coin three-part cards") -> [CDWorkModel] {
        let works = [room.simma, room.naomi].map { studentID -> CDWorkModel in
            let work = CoreDataTestHelpers.seedWorkModel(
                in: room.context, title: title, studentID: studentID, lessonID: room.lessonID
            )
            work.kind = .practiceLesson
            addParticipant(studentID, to: work, in: room.context)
            return work
        }
        for work in works {
            for other in works where other !== work {
                addParticipant(UUID(uuidString: other.studentID)!, to: work, in: room.context)
            }
        }
        return works
    }

    /// One row carrying both children — project-session shape.
    private func seedSharedRow(in room: Room) -> CDWorkModel {
        let work = CoreDataTestHelpers.seedWorkModel(
            in: room.context, title: "Fundamental Needs poster", studentID: room.simma, lessonID: room.lessonID
        )
        work.kind = .followUpAssignment
        addParticipant(room.simma, to: work, in: room.context)
        addParticipant(room.naomi, to: work, in: room.context)
        return work
    }

    private func addParticipant(_ studentID: UUID, to work: CDWorkModel, in context: NSManagedObjectContext) {
        let participant = CDWorkParticipantEntity(context: context)
        participant.id = UUID()
        participant.studentID = studentID.uuidString
        participant.work = work
    }

    @discardableResult
    private func checkIn(_ work: CDWorkModel, on day: Date, in context: NSManagedObjectContext) -> CDWorkCheckIn {
        CDWorkCheckIn.make(for: work, on: day, purpose: "progressCheck", in: context)
    }

    private func completionRecords(
        for work: CDWorkModel, in context: NSManagedObjectContext
    ) throws -> [CDWorkCompletionRecord] {
        try WorkCompletionService.records(for: try #require(work.id), in: context)
    }

    // MARK: - Targets

    @Test("Everyone on a fan-out group means every linked copy")
    func everyoneResolvesToAllCopies() throws {
        let room = try makeRoom()
        let copies = seedLinkedCopies(in: room)
        #expect(CoreDataTestHelpers.save(room.context))

        let rows = try WorkLogTargets.resolve(work: copies[0], in: room.context)
        #expect(Set(rows.map(\.objectID)) == Set(copies.map(\.objectID)))
    }

    @Test("A subset of children resolves to the copies they own")
    func subsetResolvesToOwnedCopies() throws {
        let room = try makeRoom()
        let copies = seedLinkedCopies(in: room)
        #expect(CoreDataTestHelpers.save(room.context))

        let rows = try WorkLogTargets.resolve(work: copies[0], students: [room.naomi], in: room.context)
        #expect(rows.count == 1)
        #expect(rows.first?.studentID == room.naomi.uuidString)
    }

    @Test("A shared row refuses a status for some of its children")
    func sharedRowRefusesSubset() throws {
        let room = try makeRoom()
        let shared = seedSharedRow(in: room)
        #expect(CoreDataTestHelpers.save(room.context))

        #expect(throws: WorkLogTargets.TargetError.self) {
            try WorkLogTargets.resolve(work: shared, students: [room.naomi], in: room.context)
        }
        // Naming everyone on it is fine.
        let rows = try WorkLogTargets.resolve(work: shared, students: [room.simma, room.naomi], in: room.context)
        #expect(rows.count == 1)
    }

    // MARK: - Logging

    @Test("Closing completes today's check-in and skips later ones where they are")
    func closingSettlesCheckIns() throws {
        let room = try makeRoom()
        let work = seedLinkedCopies(in: room)[0]
        let todays = checkIn(work, on: room.today, in: room.context)
        let later = checkIn(work, on: room.nextWeek, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        let receipt = try WorkLogService.log(
            [.init(work: work, status: .mastered)], on: room.today, context: room.context
        )

        #expect(work.status == .mastered)
        #expect(work.completedAt == room.today)
        #expect(todays.status == .completed)
        #expect(later.status == .skipped)
        #expect(later.date == room.nextWeek, "a skipped check-in keeps the day it was planned for")
        #expect(receipt.closed == 1)
        #expect(receipt.checkInsSettled == 2)
    }

    @Test("An open status completes today's check-in and leaves later ones scheduled")
    func openStatusKeepsFutureCheckIns() throws {
        let room = try makeRoom()
        let work = seedLinkedCopies(in: room)[0]
        let todays = checkIn(work, on: room.today, in: room.context)
        let later = checkIn(work, on: room.nextWeek, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        try WorkLogService.log([.init(work: work, status: .review)], on: room.today, context: room.context)

        #expect(work.status == .review)
        #expect(work.completedAt == nil)
        #expect(todays.status == .completed)
        #expect(later.status == .scheduled)
    }

    @Test("A child seen but unchanged still has her check-in logged")
    func unchangedEntryStillLogsTheCheckIn() throws {
        let room = try makeRoom()
        let work = seedLinkedCopies(in: room)[0]
        let todays = checkIn(work, on: room.today, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        try WorkLogService.log([.init(work: work)], on: room.today, context: room.context)

        #expect(work.status == .active)
        #expect(todays.status == .completed)
    }

    @Test("Closing a linked copy records the completion for its child only")
    func closingWritesOneCompletionRecordPerCopy() throws {
        let room = try makeRoom()
        let copies = seedLinkedCopies(in: room)
        #expect(CoreDataTestHelpers.save(room.context))

        try WorkLogService.log(
            [.init(work: copies[0], status: .keepPracticing, note: "Needs the trinomial cube again")],
            on: room.today, context: room.context
        )

        let records = try completionRecords(for: copies[0], in: room.context)
        #expect(records.count == 1)
        #expect(records.first?.studentID == room.simma.uuidString)
        #expect(records.first?.latestUnifiedNoteText == "Needs the trinomial cube again")
        #expect(try completionRecords(for: copies[1], in: room.context).isEmpty)
        #expect(copies[1].status == .active, "the sibling's row is untouched")
    }

    @Test("Closing a shared row records every child on it")
    func closingSharedRowRecordsEveryone() throws {
        let room = try makeRoom()
        let shared = seedSharedRow(in: room)
        #expect(CoreDataTestHelpers.save(room.context))

        try WorkLogService.log([.init(work: shared, status: .mastered)], on: room.today, context: room.context)

        let students = Set(try completionRecords(for: shared, in: room.context).map(\.studentID))
        #expect(students == [room.simma.uuidString, room.naomi.uuidString])
    }

    @Test("The note lands on the row, scoped to the child, and on the day's check-in")
    func noteIsFiledOnRowAndCheckIn() throws {
        let room = try makeRoom()
        let work = seedLinkedCopies(in: room)[0]
        let todays = checkIn(work, on: room.today, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))

        try WorkLogService.log(
            [.init(work: work, status: nil, note: "Matched all the coins to the cards")],
            on: room.today, context: room.context
        )

        let notes = (work.unifiedNotes?.allObjects as? [CDNote]) ?? []
        let note = try #require(notes.first)
        #expect(note.body == "Matched all the coins to the cards")
        #expect(note.workCheckIn === todays)
        if case .student(let id) = note.scope {
            #expect(id == room.simma)
        } else {
            Issue.record("expected a single-child scope, got \(note.scope)")
        }
    }

    @Test("Reopening clears the completion date")
    func reopeningClearsCompletedAt() throws {
        let room = try makeRoom()
        let work = seedLinkedCopies(in: room)[0]
        #expect(CoreDataTestHelpers.save(room.context))
        try WorkLogService.log([.init(work: work, status: .mastered)], on: room.today, context: room.context)
        #expect(work.completedAt != nil)

        try WorkLogService.log([.init(work: work, status: .active)], on: room.today, context: room.context)

        #expect(work.status == .active)
        #expect(work.completedAt == nil)
        #expect(work.participant(for: room.simma)?.completedAt == nil)
    }

    // MARK: - Undo

    @Test("Undo restores every row, participant and check-in and removes what was created")
    func undoRestoresEverything() throws {
        let room = try makeRoom()
        let copies = seedLinkedCopies(in: room)
        let todays = checkIn(copies[0], on: room.today, in: room.context)
        let later = checkIn(copies[0], on: room.nextWeek, in: room.context)
        #expect(CoreDataTestHelpers.save(room.context))
        let touchedBefore = copies[0].lastTouchedAt

        let receipt = try WorkLogService.log(
            [.init(work: copies[0], status: .mastered, note: "Done with these")],
            on: room.today, context: room.context
        )
        #expect(try completionRecords(for: copies[0], in: room.context).count == 1)

        try WorkLogService.undo(receipt.token, context: room.context)

        #expect(copies[0].status == .active)
        #expect(copies[0].completedAt == nil)
        #expect(copies[0].lastTouchedAt == touchedBefore)
        #expect(copies[0].participant(for: room.simma)?.completedAt == nil)
        #expect(todays.status == .scheduled)
        #expect(later.status == .scheduled)
        #expect(try completionRecords(for: copies[0], in: room.context).isEmpty)
        let remainingNotes = (copies[0].unifiedNotes?.allObjects as? [CDNote]) ?? []
        #expect(remainingNotes.isEmpty)
    }

    @Test("Logging nothing is refused")
    func emptyLogIsRefused() throws {
        let room = try makeRoom()
        #expect(throws: WorkLogService.LogError.self) {
            try WorkLogService.log([], context: room.context)
        }
    }
}
