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

    private func freshDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "PresentationSessionTimedCheckInTests.\(UUID().uuidString)"))
    }

    private func session(
        _ fixture: Fixture, timed: [UUID: Date], defaults given: UserDefaults? = nil
    ) throws -> PresentationSession {
        let session = PresentationSession(presentationID: try #require(fixture.assignment.id))
        let defaults = try given ?? freshDefaults()
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

    // MARK: - Review fixes (Phase 7)

    @Test("Reopened after Done with a note added, each child keeps her own day")
    func reopenedKeepsEachChildsDay() throws {
        let fixture = try makeFixture()
        let adaDay = days(from: 3)
        let benDay = days(from: 6)
        try done(try session(fixture, timed: [fixture.ada: adaDay, fixture.ben: benDay]), fixture)

        let reopened = try session(fixture, timed: [fixture.ada: adaDay, fixture.ben: benDay])
        reopened.groupNote = "Both kept going after the presentation."
        try done(reopened, fixture)

        let checks = try checkDays(fixture)
        #expect(checks[fixture.ada.uuidString] == [adaDay])
        #expect(checks[fixture.ben.uuidString] == [benDay])
        let rows = try reviewDays(fixture)
        #expect(rows[fixture.ada.uuidString] == adaDay)
        #expect(rows[fixture.ben.uuidString] == benDay)
    }

    @Test("Reopened after Done, a check-in moved by hand stays where it was moved")
    func reopenedKeepsHandMovedCheckIn() throws {
        let fixture = try makeFixture()
        let adaDay = days(from: 3)
        let benDay = days(from: 6)
        try done(try session(fixture, timed: [fixture.ada: adaDay, fixture.ben: benDay]), fixture)

        let id = try #require(fixture.assignment.id)
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(
            format: "presentationID == %@ AND studentID == %@", id.uuidString, fixture.ben.uuidString
        )
        let benWork = try #require(fixture.context.safeFetch(request).first)
        let benCheck = try #require(WorkLogService.scheduledCheckIns(of: benWork, in: fixture.context).first)
        let moved = days(from: 12)
        try WorkCheckInService(context: fixture.context).reschedule(benCheck, to: moved)

        let reopened = try session(fixture, timed: [fixture.ada: adaDay, fixture.ben: benDay])
        reopened.groupNote = "A note after the move."
        try done(reopened, fixture)

        let checks = try checkDays(fixture)
        #expect(checks[fixture.ada.uuidString] == [adaDay])
        #expect(checks[fixture.ben.uuidString] == [moved])
    }

    @Test("Reopened after Done, a day the guide picks still goes to every child")
    func reopenedPickedDayGoesToEveryone() throws {
        let fixture = try makeFixture()
        try done(try session(fixture, timed: [fixture.ada: days(from: 3), fixture.ben: days(from: 6)]), fixture)

        let picked = days(from: 9)
        let reopened = try session(fixture, timed: [:])
        reopened.pickCheckIn(.on(picked))
        try done(reopened, fixture)

        let checks = try checkDays(fixture)
        #expect(checks[fixture.ada.uuidString] == [picked])
        #expect(checks[fixture.ben.uuidString] == [picked])
        let rows = try reviewDays(fixture)
        #expect(rows[fixture.ada.uuidString] == picked)
        #expect(rows[fixture.ben.uuidString] == picked)
    }

    @Test("Later, then Done, gives each child her own timed day, as Done straight away does")
    func laterKeepsTimedDays() throws {
        let fixture = try makeFixture()
        let adaDay = days(from: 3)
        let benDay = days(from: 6)
        let defaults = try freshDefaults()
        let id = try #require(fixture.assignment.id)
        let first = try session(fixture, timed: [fixture.ada: adaDay, fixture.ben: benDay], defaults: defaults)
        PresentationSessionDraftStore.save(first.draft, presentationID: id, defaults: defaults)

        let reopened = try session(fixture, timed: [fixture.ada: adaDay, fixture.ben: benDay], defaults: defaults)
        #expect(reopened.checkIn == .on(adaDay))
        try done(reopened, fixture)

        let checks = try checkDays(fixture)
        #expect(checks[fixture.ada.uuidString] == [adaDay])
        #expect(checks[fixture.ben.uuidString] == [benDay])
    }

    @Test("Later keeps a picked day for every child")
    func laterKeepsPickedDay() throws {
        let fixture = try makeFixture()
        let picked = days(from: 10)
        let defaults = try freshDefaults()
        let id = try #require(fixture.assignment.id)
        let first = try session(fixture, timed: [fixture.ada: days(from: 3), fixture.ben: days(from: 6)], defaults: defaults)
        first.pickCheckIn(.on(picked))
        PresentationSessionDraftStore.save(first.draft, presentationID: id, defaults: defaults)

        let reopened = try session(fixture, timed: [fixture.ada: days(from: 3), fixture.ben: days(from: 6)], defaults: defaults)
        #expect(reopened.checkInDaysForDone.isEmpty)
        try done(reopened, fixture)

        let checks = try checkDays(fixture)
        #expect(checks[fixture.ada.uuidString] == [picked])
        #expect(checks[fixture.ben.uuidString] == [picked])
    }

    @Test("A draft saved before per-child days still reads, with its day for everyone")
    func oldDraftStillReads() throws {
        let json = #"{"everyone":"practice","overrides":{},"checkInDay":0,"savedAt":0}"#
        let draft = try JSONDecoder().decode(PresentationSessionDraftStore.Draft.self, from: Data(json.utf8))
        #expect(draft.timedCheckIns == nil)
    }
}
