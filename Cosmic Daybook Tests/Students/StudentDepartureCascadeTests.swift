import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Leaving and coming back (domain logic review 2026-11-20, R7): status and
/// last day are written together, the cascade takes her off only what lies
/// after her last day, and re-enrolling un-skips the year-plan entries her
/// departure skipped, and no others.
@Suite("Student departure cascade")
@MainActor
struct StudentDepartureCascadeTests {
    private let calendar = AppCalendar.shared

    /// November 2026: Wednesday 18 is today, Friday 20 her last day.
    private func day(_ dayOfMonth: Int, hour: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: dayOfMonth, hour: hour))!
    }

    private struct Room {
        let context: NSManagedObjectContext
        let maya: CDStudent
        let mayaID: UUID
        let lesson: CDLesson
        var repository: StudentRepository { StudentRepository(context: context) }
    }

    private func makeRoom() throws -> Room {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stern")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Rhombus")
        #expect(CoreDataTestHelpers.save(context))
        return Room(context: context, maya: maya, mayaID: try #require(maya.id), lesson: lesson)
    }

    @discardableResult
    private func seedEntry(_ room: Room, on day: Date?, status: YearPlanEntryStatus = .planned) -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: room.context)
        entry.studentID = room.mayaID.uuidString
        entry.lessonID = room.lesson.id?.uuidString ?? ""
        entry.plannedDate = day
        entry.sequenceGroupKey = "Geometry::Quadrilaterals"
        entry.statusRaw = status.rawValue
        return entry
    }

    private func seedPlan(_ room: Room, on day: Date?) -> CDLessonAssignment {
        let plan = PresentationFactory.makeDraft(lesson: room.lesson, students: [room.maya], context: room.context)
        if let day { plan.schedule(for: day, using: calendar) }
        return plan
    }

    private func herPlans(_ room: Room) -> [CDLessonAssignment] {
        StudentDeparturePlans.futurePlans(for: room.mayaID, in: room.context)
    }

    @Test("Leaving on Friday keeps this week's plans and entries and comes off what's after")
    func futureLastDayKeepsThisWeek() throws {
        let room = try makeRoom()
        let thursdayPlan = seedPlan(room, on: day(19))
        let mondayPlan = seedPlan(room, on: day(23))
        let thursdayEntry = seedEntry(room, on: day(19))
        let laterEntry = seedEntry(room, on: day(30))
        #expect(CoreDataTestHelpers.save(room.context))

        let change = room.repository.updateEnrollment(
            room.maya, status: .withdrawn, lastDay: day(20, hour: 15), now: day(18), ledger: .inMemory()
        )
        #expect(room.maya.enrollmentStatus == .withdrawn)
        #expect(room.maya.dateWithdrawn == day(20, hour: 15))
        #expect(change.departure?.entriesSkipped == 1)
        #expect(!thursdayPlan.isDeleted)
        #expect(mondayPlan.isDeleted)
        #expect(thursdayEntry.status == .planned)
        #expect(laterEntry.status == .skipped)
    }

    @Test("Re-enrolling un-skips the entries her departure skipped, and not one skipped by hand")
    func reEnrollingUnskips() throws {
        let room = try makeRoom()
        let ledger = DepartureSkipLedger.inMemory()
        let first = seedEntry(room, on: day(23))
        let second = seedEntry(room, on: day(30))
        let byHand = seedEntry(room, on: day(25), status: .skipped)
        #expect(CoreDataTestHelpers.save(room.context))

        room.repository.updateEnrollment(
            room.maya, status: .transferred, lastDay: day(20), now: day(18), ledger: ledger
        )
        #expect(first.status == .skipped)
        #expect(second.status == .skipped)
        #expect(CoreDataTestHelpers.save(room.context))

        let back = room.repository.updateEnrollment(room.maya, status: .enrolled, lastDay: nil, ledger: ledger)
        #expect(back.entriesRestored == 2)
        #expect(room.maya.enrollmentStatus == .enrolled)
        #expect(room.maya.dateWithdrawn == nil)
        #expect(first.status == .planned)
        #expect(second.status == .planned)
        #expect(byHand.status == .skipped)
        // The list is spent: leaving and coming back again starts afresh.
        #expect(ledger.ids(for: room.mayaID).isEmpty)
    }

    @Test("Once her last day has passed, her own open work closes as Incomplete; shared work stays open")
    func pastLastDayClosesHerWork() throws {
        let room = try makeRoom()
        let ora = CoreDataTestHelpers.seedStudent(in: room.context, firstName: "Ora", lastName: "Levi")
        let lessonID = try #require(room.lesson.id)
        let hers = CoreDataTestHelpers.seedWorkModel(
            in: room.context, title: "Rhombus drawing", studentID: room.mayaID, lessonID: lessonID
        )
        let shared = CoreDataTestHelpers.seedWorkModel(
            in: room.context, title: "Quadrilateral poster", studentID: room.mayaID, lessonID: lessonID
        )
        for child in [room.mayaID, try #require(ora.id)] {
            let participant = CDWorkParticipantEntity(context: room.context)
            participant.id = UUID()
            participant.studentID = child.uuidString
            participant.work = shared
        }
        #expect(CoreDataTestHelpers.save(room.context))

        let change = room.repository.updateEnrollment(
            room.maya, status: .withdrawn, lastDay: day(20), now: day(23), ledger: .inMemory()
        )
        #expect(change.departure?.workClosed == 1)
        #expect(hers.status == .incomplete)
        #expect(shared.status == .active)
    }

    @Test("Saving a child who left with no last day keeps her with none, and runs nothing")
    func departedWithNoDateStaysUndated() throws {
        let room = try makeRoom()
        room.maya.enrollmentStatus = .transferred
        let entry = seedEntry(room, on: day(30))
        #expect(CoreDataTestHelpers.save(room.context))

        // The student page passes her status and date on every save.
        #expect(room.repository.updateStudent(
            id: room.mayaID, firstName: "Mya", enrollmentStatus: .transferred, dateWithdrawn: .some(nil),
            ledger: .inMemory()
        ))
        #expect(room.maya.dateWithdrawn == nil)
        #expect(!room.maya.isInClass(on: day(16)))
        #expect(entry.status == .planned)
    }

    @Test("Keep on the departure alert changes the status and date only")
    func keepChangesOnlyTheFields() throws {
        let room = try makeRoom()
        let entry = seedEntry(room, on: day(30))
        #expect(CoreDataTestHelpers.save(room.context))

        let change = room.repository.updateEnrollment(
            room.maya, status: .withdrawn, lastDay: day(20), carryOutDeparture: false, now: day(18),
            ledger: .inMemory()
        )
        #expect(change.departure == nil)
        #expect(room.maya.enrollmentStatus == .withdrawn)
        #expect(entry.status == .planned)
    }

    // MARK: - The rest, once her last day has passed (Phase 10 review, finding 1)

    @Test("Leaving today owes the rest, and the first launch after her last day finishes it, once")
    func owedCascadeFinishesAfterHerLastDay() throws {
        let room = try makeRoom()
        let ledger = DepartureSkipLedger.inMemory()
        let lessonID = try #require(room.lesson.id)
        _ = seedPlan(room, on: nil)
        _ = seedPlan(room, on: day(16))
        let undatedEntry = seedEntry(room, on: nil)
        let work = CoreDataTestHelpers.seedWorkModel(
            in: room.context, title: "Rhombus drawing", studentID: room.mayaID, lessonID: lessonID
        )
        #expect(CoreDataTestHelpers.save(room.context))

        // Wednesday is her last day: nothing is after it yet.
        room.repository.updateEnrollment(room.maya, status: .withdrawn, lastDay: day(18), now: day(18), ledger: ledger)
        #expect(CoreDataTestHelpers.save(room.context))
        #expect(herPlans(room).count == 2)
        #expect(ledger.isOwed(room.mayaID))

        // Later that day, and during a first download, the launch waits.
        #expect(StudentDeparture.finishOwedAndSave(
            in: room.context, now: day(18, hour: 15), firstDownloadPending: false, ledger: ledger
        ) == 0)
        #expect(StudentDeparture.finishOwedAndSave(
            in: room.context, now: day(19), firstDownloadPending: true, ledger: ledger
        ) == 0)
        #expect(herPlans(room).count == 2)
        #expect(undatedEntry.status == .planned)
        #expect(work.status == .active)

        // Thursday's launch finishes it: the Inbox and overdue plans, the
        // undated entry and her own work.
        #expect(StudentDeparture.finishOwedAndSave(
            in: room.context, now: day(19), firstDownloadPending: false, ledger: ledger
        ) == 1)
        #expect(herPlans(room).isEmpty)
        #expect(undatedEntry.status == .skipped)
        #expect(work.status == .incomplete)
        #expect(!ledger.isOwed(room.mayaID))
        #expect(!room.context.hasChanges, "saved")

        // A second launch (or a second device) finds nothing left to do.
        #expect(StudentDeparture.finishOwedAndSave(
            in: room.context, now: day(20), firstDownloadPending: false, ledger: ledger
        ) == 0)
    }

    @Test("Keep Plans owes nothing, and coming back clears what was owed")
    func keepAndComingBackOweNothing() throws {
        let room = try makeRoom()
        let ledger = DepartureSkipLedger.inMemory()
        _ = seedPlan(room, on: nil)
        #expect(CoreDataTestHelpers.save(room.context))

        room.repository.updateEnrollment(
            room.maya, status: .withdrawn, lastDay: day(18), carryOutDeparture: false, now: day(18), ledger: ledger
        )
        #expect(!ledger.isOwed(room.mayaID))
        #expect(CoreDataTestHelpers.save(room.context))
        #expect(StudentDeparture.finishOwed(in: room.context, now: day(19), ledger: ledger).isEmpty)
        #expect(herPlans(room).count == 1)

        // Moving her last day with Remove owes it again; coming back clears it.
        room.repository.updateEnrollment(room.maya, status: .withdrawn, lastDay: day(20), now: day(18), ledger: ledger)
        #expect(ledger.isOwed(room.mayaID))
        room.repository.updateEnrollment(room.maya, status: .enrolled, lastDay: nil, now: day(18), ledger: ledger)
        #expect(!ledger.isOwed(room.mayaID))
    }

    @Test("The student page asks about what comes off later too, but not this week's lessons")
    func questionCountsTheWholeCascade() throws {
        let room = try makeRoom()
        let lessonID = try #require(room.lesson.id)
        let inbox = seedPlan(room, on: nil)
        let thursday = seedPlan(room, on: day(19))
        let monday = seedPlan(room, on: day(23))
        _ = CoreDataTestHelpers.seedWorkModel(
            in: room.context, title: "Rhombus drawing", studentID: room.mayaID, lessonID: lessonID
        )
        #expect(CoreDataTestHelpers.save(room.context))

        let now = StudentDeparture.pending(
            studentID: room.mayaID, lastDay: day(20), in: room.context, now: day(18)
        )
        #expect(now.plans.map(\.objectID) == [monday.objectID])
        #expect(now.openWork.isEmpty)

        let asked = StudentDeparture.pending(
            studentID: room.mayaID, lastDay: day(20), in: room.context, now: day(18), eventually: true
        )
        #expect(Set(asked.plans.map(\.objectID)) == [inbox.objectID, monday.objectID])
        #expect(!asked.plans.contains { $0.objectID == thursday.objectID })
        #expect(asked.openWork.count == 1)
    }
}
