import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-10, P2 #61, #65's recall check, #70, #72's fetch caps and
/// Find Students item, and #90's daylight-saving `schedule(onDay:)`.
@Suite("Students and presentations small fixes (bug hunt 2026-10-10)")
@MainActor
struct StudentsSmallFixesFix1010ITests {

    // MARK: - #61 The birthday stand-in

    @Test("A date picker still showing its stand-in saves nothing; a changed one saves")
    func editedDateKeepsMissingDatesMissing() {
        let standIn = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(StudentDetailView.editedDate(standIn, placeholder: standIn) == nil)
        let chosen = standIn.addingTimeInterval(-86_400 * 3_000)
        #expect(StudentDetailView.editedDate(chosen, placeholder: standIn) == chosen)
        #expect(StudentDetailView.editedDate(chosen, placeholder: nil) == chosen)
    }

    // MARK: - #65 A shaky recall check gates only that child

    private func recall(
        _ outcome: RecallOutcome, for student: CDStudent, lesson: CDLesson, in context: NSManagedObjectContext
    ) throws {
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        let service = RecallService(context: context, saveCoordinator: coordinator, schoolYearStore: SchoolYearStore())
        let entry = RecallQueueEntry(
            id: UUID().uuidString,
            studentID: try #require(student.id).uuidString,
            area: lesson.area,
            sequence: lesson.sequence,
            frontierLessonID: try #require(lesson.id),
            frontierLessonName: lesson.name,
            frontierOrderInSequence: 1,
            frontierMasteredAt: nil,
            coveredLessons: [],
            lastCheckedAt: nil,
            dueReason: .spacedDue
        )
        #expect(service.record(entry: entry, outcome: outcome, note: ""))
    }

    private func given(
        _ students: [CDStudent], lesson: CDLesson, in context: NSManagedObjectContext
    ) throws -> CDLessonAssignment {
        let assignment = PresentationFactory.makeDraft(
            lessonID: try #require(lesson.id), studentIDs: try students.map { try #require($0.id) }, context: context
        )
        assignment.markPresented(at: try CoreDataTestHelpers.day("2026-09-14"))
        return assignment
    }

    @Test("Shaky on a group presentation gives that child practice work and leaves the group's flag alone")
    func shakyInAGroupIsPerChild() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben")
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        let group = try given([ada, ben], lesson: lesson, in: context)
        #expect(CoreDataTestHelpers.save(context))

        try recall(.shaky, for: ada, lesson: lesson, in: context)

        #expect(!group.needsPractice)
        let work = context.safeFetch(CDFetchRequest(CDWorkModel.self))
        #expect(work.count == 1)
        #expect(work.first?.studentID == ada.id?.uuidString)
        #expect(work.first?.presentationID == group.id?.uuidString)
        #expect(work.first?.status.isOpen == true)

        // A second shaky check doesn't add a second row.
        try recall(.shaky, for: ada, lesson: lesson, in: context)
        #expect(context.safeFetch(CDFetchRequest(CDWorkModel.self)).count == 1)
    }

    @Test("Shaky on a presentation she had alone still sets its flag")
    func shakyAloneSetsTheFlag() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let lesson = CoreDataTestHelpers.seedLesson(in: context)
        let solo = try given([ada], lesson: lesson, in: context)
        #expect(CoreDataTestHelpers.save(context))

        try recall(.shaky, for: ada, lesson: lesson, in: context)

        #expect(solo.needsPractice)
        #expect(context.safeFetch(CDFetchRequest(CDWorkModel.self)).isEmpty)
    }

    // MARK: - #70 Attendance history

    private func record(
        _ status: AttendanceStatus, on date: Date, studentID: UUID, in context: NSManagedObjectContext
    ) -> CDAttendanceRecord {
        let record = CoreDataTestHelpers.seedAttendance(in: context, studentID: studentID, date: date)
        record.status = status
        return record
    }

    @Test("A day two devices both marked counts once, and a late arrival who left early is a tardy")
    func historyTotalsDedupeAndCountTardies() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        let mondayDate = try CoreDataTestHelpers.day("2026-09-14")
        let tuesday = try CoreDataTestHelpers.day("2026-09-15")
        let wednesday = try CoreDataTestHelpers.day("2026-09-16")
        _ = record(.absent, on: mondayDate, studentID: child, in: context)
        _ = record(.absent, on: mondayDate, studentID: child, in: context)
        let lateThenLeft = record(.leftEarly, on: tuesday, studentID: child, in: context)
        lateThenLeft.statusBeforeLeavingRaw = AttendanceStatus.tardy.rawValue
        _ = record(.tardy, on: wednesday, studentID: child, in: context)
        #expect(CoreDataTestHelpers.save(context))

        let records = context.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).deduplicatedPerStudentDay()
        let range = DateRange(
            start: try CoreDataTestHelpers.day("2026-08-25"), end: try CoreDataTestHelpers.day("2027-08-25")
        )
        let totals = AttendanceHistoryYearTotals.tally(records, in: range)

        #expect(totals.absent == 1)
        #expect(totals.tardy == 2)
        #expect(totals.leftEarly == 1)
        #expect(totals.attended == 2)
    }

    // MARK: - #72 No cap on the lessons read

    @Test("Student detail reads every lesson she has, past the old 1,000-row cap")
    func studentDetailReadsPastAThousandLessons() throws {
        let dependencies = try CoreDataTestHelpers.makeDependencies()
        let context = dependencies.viewContext
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let adaID = try #require(ada.id)
        for index in 0..<1_010 {
            let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Lesson \(index)")
            _ = PresentationFactory.makeDraft(lessonID: try #require(lesson.id), studentIDs: [adaID], context: context)
        }
        // One lesson she has nothing on, which must not be read.
        CoreDataTestHelpers.seedLesson(in: context, name: "Not hers")
        #expect(CoreDataTestHelpers.save(context))

        let vm = StudentDetailViewModel(student: ada, dependencies: dependencies)
        vm.loadData(viewContext: context)
        #expect(vm.lessons.count == 1_010)
        #expect(!vm.lessons.contains { $0.name == "Not hers" })
    }

    @Test("The lesson cache holds every lesson past 2,000")
    func lessonCacheHasNoCap() throws {
        let context = try CoreDataTestHelpers.makeContext()
        for index in 0..<2_005 {
            CoreDataTestHelpers.seedLesson(in: context, name: "Lesson \(index)")
        }
        #expect(CoreDataTestHelpers.save(context))
        let service = DataQueryService(context: context)
        #expect(service.fetchAllLessons().count == 2_005)
        #expect(service.fetchLessonsDictionary().count == 2_005)
    }

    // MARK: - #72 Find Students

    @Test("Find Students shows no age for a child with no birthday and sorts her last")
    func findStudentsWithoutBirthday() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let anchor = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        anchor.birthday = try CoreDataTestHelpers.day("2017-03-01")
        let noBirthday = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben")
        let near = CoreDataTestHelpers.seedStudent(in: context, firstName: "Cy")
        near.birthday = try CoreDataTestHelpers.day("2016-01-01")
        let lesson = CoreDataTestHelpers.seedLesson(in: context)

        let result = FindStudentsService.findCandidates(
            lessonID: try #require(lesson.id),
            existingStudentIDs: [try #require(anchor.id)],
            allStudents: [anchor, noBirthday, near],
            allLessonAssignments: []
        )
        #expect(result.neverReceived.map(\.student) == [near, noBirthday])
        #expect(result.neverReceived.last?.ageString == FindStudentsService.noBirthdayText)
    }

    // MARK: - #90 Daylight-saving Sundays

    private func newYork() throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        return calendar
    }

    @Test("A day's plan lands at the morning hour on the Sundays the clocks change")
    func scheduleOnDayKeepsTheHourAcrossDaylightSaving() throws {
        let calendar = try newYork()
        let context = try CoreDataTestHelpers.makeContext()
        let assignment = CDLessonAssignment(context: context)
        for day in [DateComponents(year: 2026, month: 3, day: 8), DateComponents(year: 2026, month: 11, day: 1)] {
            let date = try #require(calendar.date(from: day))
            assignment.schedule(onDay: date, using: calendar)
            let scheduled = try #require(assignment.scheduledFor)
            #expect(calendar.component(.hour, from: scheduled) == UIConstants.morningHour)
            #expect(calendar.component(.minute, from: scheduled) == 0)
            #expect(calendar.isDate(scheduled, inSameDayAs: date))
        }
    }

    @Test("The day-half planner's base hours hold on the Sundays the clocks change")
    func dayHalfTimesKeepTheHourAcrossDaylightSaving() throws {
        let calendar = try newYork()
        let spring = try #require(calendar.date(from: DateComponents(year: 2026, month: 3, day: 8)))
        let placement = DayHalfPlanner.Placement(id: UUID(), period: .morning)
        let times = DayHalfPlanner.times(for: [placement], on: spring, using: calendar, spacingSeconds: 1)
        let time = try #require(times[placement.id])
        #expect(calendar.component(.hour, from: time) == DayPeriod.morning.baseHour)
    }
}
