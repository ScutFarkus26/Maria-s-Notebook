import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-12, Today and attendance (#46, #51).
@Suite("Today fixes 2026-10-12 (T)")
@MainActor
struct TodayFix1012TTests {

    // MARK: - Fixtures

    private func addParticipant(_ studentID: UUID, to work: CDWorkModel, in context: NSManagedObjectContext) {
        let participant = CDWorkParticipantEntity(context: context)
        participant.studentID = studentID.uuidString
        work.addToParticipants(participant)
    }

    /// One row per child, each naming the whole group, as Quick New Work and
    /// `assign_work` make them.
    private func seedLinkedCopies(
        _ studentIDs: [UUID], dueOn day: Date, in context: NSManagedObjectContext
    ) -> [CDWorkModel] {
        let lessonID = UUID()
        let works = studentIDs.map { studentID -> CDWorkModel in
            let work = CoreDataTestHelpers.seedWorkModel(
                in: context, title: "Coin three-part cards", studentID: studentID, lessonID: lessonID
            )
            work.kind = .followUpAssignment
            return work
        }
        for work in works {
            for studentID in studentIDs { addParticipant(studentID, to: work, in: context) }
            CDWorkCheckIn.make(for: work, on: day, in: context)
        }
        return works
    }

    private func followUps(
        on selected: String, levelFilter: LevelFilter = .all, in context: NSManagedObjectContext
    ) throws -> [WorkCheckInFollowUp] {
        let (start, next) = AppCalendar.dayRange(for: try CoreDataTestHelpers.day(selected))
        let fetch = TodayDataFetcher.fetchWorkData(day: start, nextDay: next, referenceDate: start, context: context)
        let all = context.safeFetch(CDFetchRequest(CDStudent.self))
        let enrolled = Dictionary(
            all.filter(\.isEnrolled).compactMap { student in student.id.map { ($0, student) } },
            uniquingKeysWith: { first, _ in first }
        )
        return TodayFollowUpLoader.build(
            fetch: fetch, day: start, nextDay: next,
            studentsByID: enrolled,
            departedStudentsByID: TodayFollowUpLoader.departedStudents(in: all),
            levelFilter: levelFilter
        )
    }

    // MARK: - #46 Linked copies are judged by their owner

    @Test("A linked copy's level filter and 'left' mark follow its owner, not her classmates")
    func linkedCopyJudgedByOwner() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Sasson", level: .lower)
        let eli = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Eli", lastName: "Rosen", level: .upper, enrollmentStatus: .withdrawn
        )
        let ana = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ana", lastName: "Tal", level: .upper)
        let mayaID = try #require(maya.id)
        let eliID = try #require(eli.id)
        let anaID = try #require(ana.id)
        let copies = seedLinkedCopies(
            [mayaID, eliID, anaID], dueOn: try CoreDataTestHelpers.day("2026-09-10"), in: context
        )
        #expect(CoreDataTestHelpers.save(context))
        let mayasCopy = copies[0]
        let elisCopy = copies[1]

        // Upper El shows Eli's and Ana's copies, not Maya's (she is Lower El).
        let upper = try followUps(on: "2026-09-11", levelFilter: .upper, in: context)
        #expect(!upper.contains { $0.work === mayasCopy })
        #expect(upper.count == 2)
        // Lower El shows only Maya's.
        let lower = try followUps(on: "2026-09-11", levelFilter: .lower, in: context)
        #expect(lower.map(\.work) == [mayasCopy])

        // Eli has left: his own copy is marked, Maya's is not.
        let all = try followUps(on: "2026-09-11", in: context)
        let mayasRow = try #require(all.first { $0.work === mayasCopy })
        let elisRow = try #require(all.first { $0.work === elisCopy })
        #expect(mayasRow.departedStudentIDs.isEmpty)
        #expect(!mayasRow.hasDepartedParticipant)
        #expect(elisRow.departedStudentIDs == [eliID])
    }

    @Test("With the context, a copy whose classmates closed theirs is still only its owner's")
    func linkedCopyWithClosedClassmatesJudgedByOwner() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Sasson", level: .lower)
        let eli = CoreDataTestHelpers.seedStudent(in: context, firstName: "Eli", lastName: "Rosen", level: .upper)
        let mayaID = try #require(maya.id)
        let eliID = try #require(eli.id)
        let copies = seedLinkedCopies([mayaID, eliID], dueOn: try CoreDataTestHelpers.day("2026-09-10"), in: context)
        copies[1].status = .mastered
        #expect(CoreDataTestHelpers.save(context))

        let (start, next) = AppCalendar.dayRange(for: try CoreDataTestHelpers.day("2026-09-11"))
        let fetch = TodayDataFetcher.fetchWorkData(day: start, nextDay: next, referenceDate: start, context: context)
        let byID: [UUID: CDStudent] = [mayaID: maya, eliID: eli]
        let upper = TodayFollowUpLoader.build(
            fetch: fetch, day: start, nextDay: next, studentsByID: byID, departedStudentsByID: [:],
            levelFilter: .upper, context: context
        )
        #expect(upper.isEmpty)
        let all = TodayFollowUpLoader.build(
            fetch: fetch, day: start, nextDay: next, studentsByID: byID, departedStudentsByID: [:],
            levelFilter: .all, context: context
        )
        let row = try #require(all.first)
        #expect(all.count == 1)
        #expect(row.countedStudentIDs == [mayaID])
        #expect(row.companionIDs == [eliID])
    }

    // MARK: - #51 Mark checked in

    @Test("Mark checked in settles every overdue check-in on the row and stamps the work as seen")
    func markCheckedInSettlesEveryOverdueCheckIn() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dechter")
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Stamp Game", studentID: try #require(etty.id))
        let today = AppCalendar.startOfDay(Date())
        let earliest = CDWorkCheckIn.make(for: work, on: AppCalendar.addingDays(-8, to: today), in: context)
        let later = CDWorkCheckIn.make(for: work, on: AppCalendar.addingDays(-3, to: today), in: context)
        let upcoming = CDWorkCheckIn.make(for: work, on: AppCalendar.addingDays(5, to: today), in: context)
        #expect(CoreDataTestHelpers.save(context))
        let item = WorkCheckInFollowUp(
            id: try #require(earliest.id), checkIn: earliest, work: work,
            dueDay: AppCalendar.startOfDay(try #require(earliest.date)), isOverdue: true,
            studentIDs: [try #require(etty.id)], departedStudentIDs: []
        )
        let before = Date().addingTimeInterval(-1)

        try TodayCheckInFollowUpActions.markCheckedIn(item, context: context)

        #expect(earliest.status == .completed)
        #expect(later.status == .completed)
        #expect(upcoming.status == .scheduled)
        // Done means checked today: the row's check-in moves to the day it was checked.
        #expect(AppCalendar.startOfDay(try #require(earliest.date)) == today)
        let touched = try #require(work.lastTouchedAt)
        #expect(touched >= before)
        #expect(!context.hasChanges)
    }

    // MARK: - #51 Names on a shared row

    @Test("Every child on a shared row is loaded for its name, not only the owner")
    func sharedRowParticipantsAreNeeded() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let owner = UUID()
        let partner = UUID()
        let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Fundamental Needs Poster", studentID: owner)
        addParticipant(owner, to: work, in: context)
        addParticipant(partner, to: work, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let (day, next) = AppCalendar.dayRange(for: Date())
        let fetch = try #require(
            TodayDataFetcher.fetchWorkData(day: day, nextDay: next, referenceDate: day, context: context)
        )
        #expect(fetch.neededStudentIDs.contains(owner))
        #expect(fetch.neededStudentIDs.contains(partner))
    }

    // MARK: - #51 Test students

    @Test("Today's Watching leaves out hidden test students")
    func watchingHidesTestStudents() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Sasson")
        let tester = CoreDataTestHelpers.seedStudent(in: context, firstName: "Danny", lastName: "De Berry")

        let hidden = TodayWatchingSectionView.watchedRoster(
            [maya, tester], testStudents: .init(show: false, namesRaw: "Danny De Berry")
        )
        #expect(hidden.map(\.objectID) == [maya.objectID])
        let shown = TodayWatchingSectionView.watchedRoster(
            [maya, tester], testStudents: .init(show: true, namesRaw: "Danny De Berry")
        )
        #expect(shown.count == 2)
    }

    @Test("The Absence and Tardy reports leave out hidden test students and keep former students")
    func reportsHideTestStudents() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let start = try CoreDataTestHelpers.day("2026-09-01")
        let end = try CoreDataTestHelpers.day("2026-10-01")
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Sasson")
        let naomi = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Naomi", lastName: "Levin", enrollmentStatus: .withdrawn,
            dateWithdrawn: try CoreDataTestHelpers.day("2026-09-15")
        )
        let tester = CoreDataTestHelpers.seedStudent(in: context, firstName: "Lil Dan", lastName: "D")

        let students = AttendanceStatusReport.reportStudents(
            [maya, naomi, tester], in: DateRange(start: start, end: end),
            testStudents: .init(show: false, namesRaw: "Danny De Berry,Lil Dan D")
        )
        #expect(Set(students.map(\.objectID)) == [maya.objectID, naomi.objectID])
    }

    // MARK: - #51 Reminders warning

    @Test("The Reminders section stays up to say a sync failed, even with nothing synced")
    func remindersShowWhenSyncFailed() {
        #expect(TodaySectionVisibility.showsReminders(overdue: 0, dueToday: 0, anytime: 0, syncFailed: true))
        #expect(!TodaySectionVisibility.showsReminders(overdue: 0, dueToday: 0, anytime: 0, syncFailed: false))
    }
}
