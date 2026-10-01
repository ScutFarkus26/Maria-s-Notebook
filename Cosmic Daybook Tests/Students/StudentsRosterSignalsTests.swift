import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The roster filters and sorts the live roster in memory, reloads only
/// attendance on an attendance change unless the table caches' own inputs
/// moved, and reads observation dates as dictionaries. These pin each.
@Suite("Students roster signals")
@MainActor
struct StudentsRosterSignalsTests {

    private func seedRoster(in context: NSManagedObjectContext) {
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Stone", level: .upper)
        ada.manualOrder = 2
        ada.birthday = Date(timeIntervalSinceReferenceDate: 400_000_000)
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben", lastName: "Hart", level: .lower)
        ben.manualOrder = 1
        ben.birthday = Date(timeIntervalSinceReferenceDate: 500_000_000)
        let cy = CoreDataTestHelpers.seedStudent(in: context, firstName: "Cy", lastName: "Lee", level: .upper)
        cy.manualOrder = 0
        cy.birthday = nil
        CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Dee", lastName: "Moss", enrollmentStatus: .withdrawn
        )
    }

    private func names(_ students: [CDStudent]) -> [String] { students.map(\.firstName) }

    @Test("The in-memory filter and sort give each scope and order")
    func filterAndSort() throws {
        let context = try CoreDataTestHelpers.makeContext()
        seedRoster(in: context)
        #expect(CoreDataTestHelpers.save(context))
        let all = context.safeFetch(CDFetchRequest(CDStudent.self))
        func list(
            _ filter: StudentsFilter, _ sort: CosmicDaybook.SortOrder, search: String = "",
            present: Set<UUID> = [], due: Set<UUID> = []
        ) -> [String] {
            names(StudentsViewModel.filteredStudents(
                all, filter: filter, sortOrder: sort, searchString: search, presentNowIDs: present, dueIDs: due
            ))
        }

        #expect(list(.all, .alphabetical) == ["Ada", "Ben", "Cy"])
        #expect(list(.all, .manual) == ["Cy", "Ben", "Ada"])
        // Youngest first; Cy has no birthday on file and sorts last.
        #expect(list(.all, .age) == ["Ben", "Ada", "Cy"])
        #expect(list(.upper, .alphabetical) == ["Ada", "Cy"])
        #expect(list(.lower, .alphabetical) == ["Ben"])
        #expect(list(.withdrawn, .alphabetical) == ["Dee"])
        #expect(list(.all, .alphabetical, search: "a") == ["Ada", "Ben"])
        #expect(list(.all, .alphabetical, search: "lee") == ["Cy"])

        let ben = try #require(all.first { $0.firstName == "Ben" }?.id)
        let cy = try #require(all.first { $0.firstName == "Cy" }?.id)
        #expect(list(.presentNow, .alphabetical, present: [ben]) == ["Ben"])
        #expect(list(.presentNow, .alphabetical).isEmpty)
        #expect(list(.dueForLesson, .alphabetical, due: [cy, ben]) == ["Ben", "Cy"])
    }

    @Test("An attendance change reloads attendance alone unless a table input moved")
    func refreshGate() throws {
        let context = try CoreDataTestHelpers.makeContext()
        seedRoster(in: context)
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads")
        #expect(CoreDataTestHelpers.save(context))
        let students = context.safeFetch(CDFetchRequest(CDStudent.self))
        let calendar = AppCalendar.shared
        let viewModel = StudentsViewModel()

        viewModel.refreshIfNeeded(viewContext: context, calendar: calendar, students: students)
        #expect(viewModel.tableCacheBuildCount == 1)
        #expect(viewModel.attendanceLoadCount == 1)

        // Nothing changed: nothing reloads.
        viewModel.refreshIfNeeded(viewContext: context, calendar: calendar, students: students)
        #expect(viewModel.tableCacheBuildCount == 1)
        #expect(viewModel.attendanceLoadCount == 1)

        let ada = try #require(students.first { $0.firstName == "Ada" })
        let adaID = try #require(ada.id)
        let mark = CoreDataTestHelpers.seedAttendance(in: context, studentID: adaID, date: Date())
        mark.statusRaw = AttendanceStatus.tardy.rawValue
        #expect(CoreDataTestHelpers.save(context))
        viewModel.refreshIfNeeded(viewContext: context, calendar: calendar, students: students)
        #expect(viewModel.tableCacheBuildCount == 1)
        #expect(viewModel.attendanceLoadCount == 2)
        #expect(viewModel.signals(for: adaID).presence == .here)
        #expect(viewModel.attendanceTaken)

        // A next-lesson pick and an observation are table inputs.
        ada.nextLessonUUIDs = [try #require(lesson.id)]
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Counted to 100")
        note.scope = .student(adaID)
        #expect(CoreDataTestHelpers.save(context))
        viewModel.refreshIfNeeded(viewContext: context, calendar: calendar, students: students)
        #expect(viewModel.tableCacheBuildCount == 2)
        #expect(viewModel.attendanceLoadCount == 2)

        let fresh = StudentsViewModel()
        fresh.loadDataOnDemand(viewContext: context, calendar: calendar, students: students)
        #expect(viewModel.cachedNextLessonNames == fresh.cachedNextLessonNames)
        #expect(viewModel.signals(for: adaID).nextLessonName == "Golden Beads")
        #expect(viewModel.signals(for: adaID).lastObserved != nil)
        #expect(viewModel.cachedLastObservationDates == fresh.cachedLastObservationDates)
        #expect(viewModel.cachedDaysSinceLastLesson == fresh.cachedDaysSinceLastLesson)
    }

    @Test("Presenting a scheduled lesson rebuilds lesson age without changing any count")
    func presentingAScheduledLessonRefreshes() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", level: .upper)
        let adaID = try #require(ada.id)
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game")
        let plan = PresentationFactory.makeDraft(lesson: lesson, students: [ada], context: context)
        #expect(CoreDataTestHelpers.save(context))
        let viewModel = StudentsViewModel()
        let students = [ada]

        viewModel.refreshIfNeeded(viewContext: context, calendar: AppCalendar.shared, students: students)
        #expect(viewModel.signals(for: adaID).schoolDaysSinceLesson == nil)

        // The old count tokens missed this: the assignment count is unchanged.
        plan.state = .presented
        plan.presentedAt = Date()
        #expect(CoreDataTestHelpers.save(context))
        viewModel.refreshIfNeeded(viewContext: context, calendar: AppCalendar.shared, students: students)
        #expect(viewModel.signals(for: adaID).schoolDaysSinceLesson == 0)
    }

    @Test("Today's marks map to presence; a duplicate row keeps the marked one")
    func presenceFromRecords() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let ids = (0..<5).map { _ in UUID() }
        let statuses: [AttendanceStatus] = [.present, .tardy, .absent, .leftEarly, .unmarked]
        var records: [CDAttendanceRecord] = []
        for (id, status) in zip(ids, statuses) {
            let record = CoreDataTestHelpers.seedAttendance(in: context, studentID: id)
            record.statusRaw = status.rawValue
            records.append(record)
        }
        let duplicate = CoreDataTestHelpers.seedAttendance(in: context, studentID: ids[4])
        duplicate.statusRaw = AttendanceStatus.absent.rawValue
        records.append(duplicate)

        let (presence, taken) = StudentsViewModel.presence(from: records)
        #expect(taken)
        #expect(presence[ids[0]] == .here)
        #expect(presence[ids[1]] == .here)
        #expect(presence[ids[2]] == .absent)
        #expect(presence[ids[3]] == .leftEarly)
        #expect(presence[ids[4]] == .absent)

        let blank = CoreDataTestHelpers.seedAttendance(in: context)
        #expect(StudentsViewModel.presence(from: [blank]).taken == false)
    }

    @Test("Signal rules: due at seven school days or none, stale at two weeks, birthdays in the coming week")
    func signalRules() throws {
        #expect(RosterSignalRules.isDue(schoolDaysSinceLesson: nil))
        #expect(RosterSignalRules.isDue(schoolDaysSinceLesson: 7))
        #expect(!RosterSignalRules.isDue(schoolDaysSinceLesson: 6))

        let calendar = AppCalendar.shared
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 10)))
        let thirteenDays = try #require(calendar.date(byAdding: .day, value: -13, to: now))
        let fourteenDays = try #require(calendar.date(byAdding: .day, value: -14, to: now))
        #expect(RosterSignalRules.isObservationStale(nil, now: now, calendar: calendar))
        #expect(!RosterSignalRules.isObservationStale(thirteenDays, now: now, calendar: calendar))
        #expect(RosterSignalRules.isObservationStale(fourteenDays, now: now, calendar: calendar))

        let birthdayToday = try #require(calendar.date(from: DateComponents(year: 2016, month: 10, day: 1)))
        let birthdayTuesday = try #require(calendar.date(from: DateComponents(year: 2016, month: 10, day: 6)))
        let birthdayNextWeek = try #require(calendar.date(from: DateComponents(year: 2016, month: 10, day: 8)))
        #expect(RosterSignalRules.daysUntilSoonBirthday(birthdayToday, calendar: calendar, today: now) == 0)
        #expect(RosterSignalRules.daysUntilSoonBirthday(birthdayTuesday, calendar: calendar, today: now) == 5)
        #expect(RosterSignalRules.daysUntilSoonBirthday(birthdayNextWeek, calendar: calendar, today: now) == nil)
        #expect(RosterSignalText.birthday(inDays: 5, calendar: calendar, today: now) == "Birthday Tue")

        #expect(RosterSignalText.lesson(nil) == "No lessons this year")
        #expect(RosterSignalText.lesson(1) == "Lesson 1 day ago")
        #expect(RosterSignalText.observed(thirteenDays, calendar: calendar, now: now) == "Observed 13 days ago")
        #expect(RosterSignalText.observed(fourteenDays, calendar: calendar, now: now) == "Observed 2 wks ago")
    }

    @Test("Observation dates read as dictionaries equal the object path (SQLite)")
    func observationDatesDictionaryMatchesObjects() throws {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben")
        let cy = CoreDataTestHelpers.seedStudent(in: context, firstName: "Cy")
        let adaID = try #require(ada.id)
        let benID = try #require(ben.id)
        let cyID = try #require(cy.id)
        let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

        let direct = CoreDataTestHelpers.seedNote(in: context, body: "Direct")
        direct.scope = .student(adaID)
        direct.updatedAt = base.addingTimeInterval(100)

        let older = CoreDataTestHelpers.seedNote(in: context, body: "Older")
        older.scope = .student(adaID)
        older.updatedAt = nil
        older.createdAt = base

        let group = CoreDataTestHelpers.seedNote(in: context, body: "Group")
        group.scope = .students([benID, cyID])
        group.updatedAt = base.addingTimeInterval(200)
        for id in [benID, cyID] {
            let link = CDNoteStudentLink(context: context)
            link.studentIDUUID = id
            link.note = group
        }

        let wholeClass = CoreDataTestHelpers.seedNote(in: context, body: "Everyone")
        wholeClass.scope = .all
        wholeClass.updatedAt = base.addingTimeInterval(900)
        let classLink = CDNoteStudentLink(context: context)
        classLink.studentIDUUID = cyID
        classLink.note = wholeClass
        try context.save()

        #expect(StudentsViewModel.directNoteRows(in: context) != nil)
        #expect(StudentsViewModel.linkRows(in: context) != nil)
        let wanted: Set<UUID> = [adaID, benID]
        let dictionaryPath = StudentsViewModel.latestObservationDates(for: wanted, in: context)

        // Any unsaved change sends the read down the object path.
        CoreDataTestHelpers.seedLesson(in: context)
        #expect(context.hasChanges)
        let objectPath = StudentsViewModel.latestObservationDates(for: wanted, in: context)

        #expect(dictionaryPath == objectPath)
        #expect(dictionaryPath[adaID] == base.addingTimeInterval(100))
        #expect(dictionaryPath[benID] == base.addingTimeInterval(200))
        #expect(dictionaryPath[cyID] == nil)
    }
}
