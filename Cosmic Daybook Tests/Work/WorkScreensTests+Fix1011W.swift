import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-11, #16 and #19–#25: Schedule on a work card, whose a
/// linked copy is in the Work column, its child filter and the Works log,
/// Hide Scheduled Work, untagged work, the log's titles, and set-aside work.
@Suite("Work Screens (fix 10-11 W)")
@MainActor
struct WorkScreensFix1011WTests {

    private struct Fixture {
        let context: NSManagedObjectContext
        let lesson: CDLesson
        let maya: UUID
        let eli: UUID
        let ana: UUID

        var lessonID: UUID { lesson.id ?? UUID() }
    }

    private func makeFixture() throws -> Fixture {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Checkerboard")
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let eli = CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli", lastName: "Park")
        let ana = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ana", lastName: "Ruiz")
        CoreDataTestHelpers.save(context)
        return Fixture(
            context: context, lesson: lesson,
            maya: try #require(maya.id), eli: try #require(eli.id), ana: try #require(ana.id)
        )
    }

    /// One Quick New Work for these children: a row per child, each naming
    /// every other child, as the sheet makes them.
    private func quickNewWork(_ fixture: Fixture, for students: [UUID]) throws -> [CDWorkModel] {
        let repository = WorkRepository(context: fixture.context)
        let works = try students.map { studentID in
            try repository.createWork(
                studentID: studentID, lessonID: fixture.lessonID, kind: .practiceLesson, saveImmediately: false
            )
        }
        for work in works {
            for other in works where other !== work {
                let participant = CDWorkParticipantEntity(context: fixture.context)
                participant.id = UUID()
                participant.studentID = other.studentID
                participant.work = work
            }
        }
        CoreDataTestHelpers.save(fixture.context)
        return works
    }

    /// One row carrying several children, as project work is made.
    private func sharedRow(_ fixture: Fixture, owner: UUID, children: [UUID]) -> CDWorkModel {
        let work = CDWorkModel(context: fixture.context)
        work.lessonID = fixture.lessonID.uuidString
        work.studentID = owner.uuidString
        work.status = .active
        work.createdAt = Date()
        for child in children {
            let participant = CDWorkParticipantEntity(context: fixture.context)
            participant.id = UUID()
            participant.studentID = child.uuidString
            participant.work = work
        }
        CoreDataTestHelpers.save(fixture.context)
        return work
    }

    // MARK: - Schedule (#16, #25)

    @Test("Schedule leaves a finished check-in and its note on their day, and makes a new one")
    func scheduleKeepsFinishedCheckIns() throws {
        let fixture = try makeFixture()
        let work = try #require(try quickNewWork(fixture, for: [fixture.maya]).first)
        let sep15 = try CoreDataTestHelpers.day("2026-09-15")
        let done = CDWorkCheckIn.make(
            for: work, on: sep15, purpose: "Progress Check", status: .completed, in: fixture.context
        )
        done.setLegacyNoteText("Kept working on the second row", in: fixture.context)
        CoreDataTestHelpers.save(fixture.context)

        let tomorrow = try CoreDataTestHelpers.day("2026-10-12")
        let scheduled = WorkCheckInService(context: fixture.context).scheduleCheck(for: work, on: tomorrow)

        #expect(done.date == sep15)
        #expect(done.status == .completed)
        #expect(scheduled !== done)
        #expect(scheduled.date == AppCalendar.startOfDay(tomorrow))
        #expect(scheduled.status == .scheduled)
        #expect(work.dueAt == AppCalendar.startOfDay(tomorrow))
        #expect(WorkLogService.checkIns(of: work, in: fixture.context).count == 2)
    }

    @Test("Schedule moves the earliest still-scheduled check-in rather than making a second")
    func scheduleMovesTheScheduledCheckIn() throws {
        let fixture = try makeFixture()
        let work = try #require(try quickNewWork(fixture, for: [fixture.maya]).first)
        let done = CDWorkCheckIn.make(
            for: work, on: try CoreDataTestHelpers.day("2026-09-15"), status: .completed, in: fixture.context
        )
        let friday = CDWorkCheckIn.make(for: work, on: try CoreDataTestHelpers.day("2026-10-16"), in: fixture.context)
        CoreDataTestHelpers.save(fixture.context)

        let tomorrow = try CoreDataTestHelpers.day("2026-10-12")
        let moved = WorkCheckInService(context: fixture.context).scheduleCheck(for: work, on: tomorrow)

        #expect(moved === friday)
        #expect(friday.date == AppCalendar.startOfDay(tomorrow))
        #expect(done.date == (try CoreDataTestHelpers.day("2026-09-15")))
        #expect(WorkLogService.checkIns(of: work, in: fixture.context).count == 2)
    }

    // MARK: - Whose a linked copy is (#19)

    @Test("Maya's closed copy plus Eli's open one: Maya isn't carrying it in the Work column")
    func quietColumnReadsOwnCopyOnly() throws {
        let fixture = try makeFixture()
        let copies = try quickNewWork(fixture, for: [fixture.maya, fixture.eli])
        copies[0].status = .mastered
        CoreDataTestHelpers.save(fixture.context)
        let open = [copies[1]]

        let visibility = WorkVisibility(covering: open, in: fixture.context)
        let rollup = QuietStudentsOrder.daysSinceTouchByStudent(in: open, visibility: visibility) { _ in 4 }

        #expect(rollup[fixture.eli] == 4)
        #expect(rollup[fixture.maya] == nil)
    }

    @Test("A genuinely shared row still counts for every child on it")
    func sharedRowCountsForEveryone() throws {
        let fixture = try makeFixture()
        let row = sharedRow(fixture, owner: fixture.maya, children: [fixture.maya, fixture.eli])

        let visibility = WorkVisibility(covering: [row], in: fixture.context)
        #expect(QuietStudentsOrder.openStudentIDs(of: row, visibility: visibility) == [fixture.maya, fixture.eli])
    }

    @Test("Picking Maya in the column shows her own copy, not Eli's and Ana's")
    func childFilterShowsOwnCopy() throws {
        let fixture = try makeFixture()
        let copies = try quickNewWork(fixture, for: [fixture.maya, fixture.eli, fixture.ana])

        let filter = WorkAgendaFilter(studentID: fixture.maya)
        let shown = filter.apply(
            to: copies, partition: LessonsAndWorkPartition(),
            visibility: WorkVisibility(covering: copies, in: fixture.context)
        )
        #expect(shown.map(\.objectID) == [copies[0].objectID])
    }

    @Test("The Works log filtered by Maya lists her copy and the shared row, not her classmates' copies")
    func worksLogChildFilterReadsPerGroup() throws {
        let fixture = try makeFixture()
        let copies = try quickNewWork(fixture, for: [fixture.maya, fixture.eli, fixture.ana])
        let shared = sharedRow(fixture, owner: fixture.eli, children: [fixture.eli, fixture.maya])
        let all = fixture.context.safeFetch(CDFetchRequest(CDWorkModel.self))
        let visibility = WorkVisibility(rows: all)

        let mayas = all.filter { WorksLogRows.matches($0, students: [fixture.maya], visibility: visibility) }
        #expect(Set(mayas.map(\.objectID)) == [copies[0].objectID, shared.objectID])
    }

    // MARK: - Hide Scheduled Work (#20)

    @Test("Hide Scheduled Work hides what the Scheduled pill shows and keeps overdue work")
    func hideScheduledKeepsOverdueWork() throws {
        let fixture = try makeFixture()
        let rows = try quickNewWork(fixture, for: [fixture.maya, fixture.eli, fixture.ana])
        let overdue = rows[0], upcoming = rows[1], unplanned = rows[2]
        let today = AppCalendar.startOfDay(Date())
        CDWorkCheckIn.make(for: overdue, on: AppCalendar.addingDays(-1, to: today), in: fixture.context)
        CDWorkCheckIn.make(for: upcoming, on: AppCalendar.addingDays(2, to: today), in: fixture.context)
        CoreDataTestHelpers.save(fixture.context)

        let partition = LessonsAndWorkPartition(
            openWork: rows, assignments: [], unresolvedFollowUpIDs: [], context: fixture.context
        )
        #expect(partition.work.attention.contains(overdue))
        #expect(partition.work.scheduled.map(\.objectID) == [upcoming.objectID])

        let filter = WorkAgendaFilter(hideScheduled: true, chip: .all)
        let shown = filter.apply(to: rows, partition: partition, visibility: WorkVisibility(rows: rows))
        #expect(Set(shown.map(\.objectID)) == [overdue.objectID, unplanned.objectID])
    }

    // MARK: - Children not on screen (#24)

    @Test("Work of a child not on the roster (a hidden test student) stays off the grid")
    func workOfHiddenChildrenIsLeftOut() throws {
        let fixture = try makeFixture()
        let mayas = try #require(try quickNewWork(fixture, for: [fixture.maya]).first)
        let anas = try #require(try quickNewWork(fixture, for: [fixture.ana]).first)
        let unclaimed = CDWorkModel(context: fixture.context)
        unclaimed.lessonID = fixture.lessonID.uuidString
        unclaimed.status = .active

        let filter = WorkAgendaFilter(rosterIDs: [fixture.maya, fixture.eli])
        let rows = [mayas, anas, unclaimed]
        let shown = filter.apply(to: rows, partition: LessonsAndWorkPartition(), visibility: WorkVisibility(rows: rows))
        #expect(shown.map(\.objectID) == [mayas.objectID, unclaimed.objectID])
    }

    // MARK: - Untagged work and titles (#21, #22)

    @Test("Untagged work is Practice in the log's type filter")
    func untaggedWorkIsPractice() throws {
        let fixture = try makeFixture()
        let work = try #require(try quickNewWork(fixture, for: [fixture.maya]).first)
        work.kind = nil

        #expect(WorksLogRows.matches(work, kind: .practiceLesson))
        #expect(!WorksLogRows.matches(work, kind: .research))
    }

    @Test("A log row with no title and no presentation reads its lesson's name")
    func untitledRowNamesItsLesson() throws {
        let fixture = try makeFixture()
        let work = try #require(try quickNewWork(fixture, for: [fixture.maya]).first)
        work.presentationID = nil
        work.title = ""

        let title = WorksLogRows.title(
            of: work, linkedLesson: nil, lessonsByID: [fixture.lessonID: fixture.lesson]
        )
        #expect(title == "Practice: Checkerboard")
    }

    // MARK: - Set-aside work (#25)

    @Test("A child whose only open work is set aside doesn't read as long quiet")
    func setAsideWorkDoesNotAge() throws {
        let fixture = try makeFixture()
        let work = try #require(try quickNewWork(fixture, for: [fixture.maya]).first)
        work.restingUntil = AppCalendar.addingDays(7, to: AppCalendar.startOfDay(Date()))

        let rollup = QuietStudentsOrder.daysSinceTouchByStudent(in: [work]) { _ in 30 }
        #expect(rollup[fixture.maya] == 0)
    }

    @Test("Set-aside work doesn't hide how long her other work has sat")
    func setAsideWorkDoesNotMaskOtherWork() throws {
        let fixture = try makeFixture()
        let resting = try #require(try quickNewWork(fixture, for: [fixture.maya]).first)
        resting.restingUntil = AppCalendar.addingDays(7, to: AppCalendar.startOfDay(Date()))
        let active = try #require(try quickNewWork(fixture, for: [fixture.maya]).first)
        let ages = [resting.objectID: 30, active.objectID: 12]

        let rollup = QuietStudentsOrder.daysSinceTouchByStudent(in: [resting, active]) { ages[$0.objectID] ?? 0 }
        #expect(rollup[fixture.maya] == 12)
    }
}
