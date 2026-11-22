import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The present-a-lesson sheet's check-in day (plan "Tide list clean-up
/// 2026-11", Phase 2): it starts from `PracticeCheckInTiming.checkInDays`, as
/// chat does, each child on her own day; a day the guide picks still wins,
/// and a record already decided keeps its day.
@Suite("Present-a-lesson sheet: timed check-in days")
@MainActor
struct PresentationSessionTimedCheckInTests {
    private struct Fixture {
        let context: NSManagedObjectContext
        let coordinator: SaveCoordinator
        let lesson: CDLesson
        let ada: UUID
        let ben: UUID
        let assignment: CDLessonAssignment
    }

    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Golden Beads: Addition", area: "Math", sequence: "Decimal System"
        )
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben")
        let today = AppCalendar.startOfDay(Date())
        let assignment = PresentationFactory.makeScheduled(
            lesson: lesson, students: [ada, ben], scheduledFor: today, context: context
        )
        try context.save()
        _ = try ImmediatePresentationRecordingService.record(
            assignment: assignment, presentedOn: today, context: context, saveCoordinator: coordinator
        )
        return Fixture(
            context: context, coordinator: coordinator, lesson: lesson,
            ada: try #require(ada.id), ben: try #require(ben.id), assignment: assignment
        )
    }

    private func days(from now: Int) -> Date {
        AppCalendar.startOfDay(AppCalendar.addingDays(now, to: Date()))
    }

    private func session(_ fixture: Fixture, timed: [UUID: Date]) throws -> PresentationSession {
        let session = PresentationSession(presentationID: try #require(fixture.assignment.id))
        let suite = "PresentationSessionTimedCheckInTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        session.loadDecisions(
            studentIDs: [fixture.ada, fixture.ben], defaultDecision: .practice,
            timedCheckIns: timed, context: fixture.context, defaults: defaults
        )
        return session
    }

    private func done(_ session: PresentationSession, _ fixture: Fixture) throws {
        _ = try PresentationSessionCommit.apply(
            session.commitInput(
                assignment: fixture.assignment, lesson: fixture.lesson,
                studentIDs: [fixture.ada, fixture.ben], lessons: [fixture.lesson]
            ),
            context: fixture.context, saveCoordinator: fixture.coordinator
        )
    }

    /// Each child's scheduled check-in days on her work from the presentation.
    private func checkDays(_ fixture: Fixture) throws -> [String: Set<Date>] {
        let id = try #require(fixture.assignment.id)
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "presentationID == %@", id.uuidString)
        var days: [String: Set<Date>] = [:]
        for work in fixture.context.safeFetch(request) {
            let scheduled = WorkLogService.scheduledCheckIns(of: work, in: fixture.context)
            days[work.studentID, default: []].formUnion(scheduled.compactMap(\.date).map(AppCalendar.startOfDay))
        }
        return days
    }

    private func reviewDays(_ fixture: Fixture) throws -> [String: Date] {
        let id = try #require(fixture.assignment.id)
        return Dictionary(
            PresentationFollowUpService.rows(for: id, in: fixture.context).compactMap { row in
                row.followUpReviewAt.map { (row.studentID, AppCalendar.startOfDay($0)) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }

    @Test("With nothing decided, the sheet shows the earliest timed day and Done gives each child hers")
    func timedDaysPerChild() throws {
        let fixture = try makeFixture()
        let adaDay = days(from: 3)
        let benDay = days(from: 6)
        let session = try session(fixture, timed: [fixture.ada: adaDay, fixture.ben: benDay])
        #expect(session.checkIn == .on(adaDay))

        try done(session, fixture)
        let checks = try checkDays(fixture)
        #expect(checks[fixture.ada.uuidString] == [adaDay])
        #expect(checks[fixture.ben.uuidString] == [benDay])
        let rows = try reviewDays(fixture)
        #expect(rows[fixture.ada.uuidString] == adaDay)
        #expect(rows[fixture.ben.uuidString] == benDay)
    }

    @Test("A day the guide picks wins for every child")
    func pickedDayWins() throws {
        let fixture = try makeFixture()
        let picked = days(from: 10)
        let session = try session(fixture, timed: [fixture.ada: days(from: 3), fixture.ben: days(from: 6)])
        session.pickCheckIn(.on(picked))

        try done(session, fixture)
        let checks = try checkDays(fixture)
        #expect(checks[fixture.ada.uuidString] == [picked])
        #expect(checks[fixture.ben.uuidString] == [picked])
    }

    @Test("A record already decided keeps its own day when the sheet opens again")
    func decidedRecordKeepsItsDay() throws {
        let fixture = try makeFixture()
        let first = try session(fixture, timed: [fixture.ada: days(from: 3), fixture.ben: days(from: 3)])
        let chosen = days(from: 8)
        first.pickCheckIn(.on(chosen))
        try done(first, fixture)

        let reopened = try session(fixture, timed: [fixture.ada: days(from: 3), fixture.ben: days(from: 3)])
        #expect(reopened.checkIn == .on(chosen))
        #expect(!reopened.checkInChanged)
        #expect(reopened.checkInDaysForDone.isEmpty)
    }
}
