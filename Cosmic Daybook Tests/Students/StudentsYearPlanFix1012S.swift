import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-12, students and the year plan: the rollover's landing date
// (#52), the closed-day count (#53), re-dating after a closed day (#57), the
// carried-over sweep's failed save (#59), taking a child off a presentation
// offers her own generated row (#47), Watching leaves out hidden test students
// (#51), and the roster's next lesson comes from her next scheduled
// presentation (#58's note).
@Suite("Students and year plan (bug hunt fixes 10-12)", .serialized)
@MainActor
struct StudentsYearPlanFix1012S {

    private let cal = AppCalendar.shared

    private func makeContext() throws -> NSManagedObjectContext {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        SchoolCalendarService.shared.invalidateCache()
        return context
    }

    private func makeStore() -> SchoolYearStore {
        let store = SchoolYearStore()
        store.publish = { _, _, _ in }
        return store
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: dayOfMonth)) ?? Date()
    }

    private func closeSchool(on date: Date, in context: NSManagedObjectContext) {
        let record = CDNonSchoolDay(context: context)
        record.date = AppCalendar.startOfDay(date)
    }

    @discardableResult
    private func seedEntry(
        in context: NSManagedObjectContext,
        student: CDStudent,
        lesson: CDLesson,
        plannedDate: Date?,
        order: Int64 = 0,
        status: YearPlanEntryStatus = .planned
    ) -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = student.id?.uuidString ?? ""
        entry.lessonID = lesson.id?.uuidString ?? ""
        entry.plannedDate = plannedDate
        entry.sequenceGroupKey = "Geometry::Polygons"
        entry.orderInSequence = order
        entry.statusRaw = status.rawValue
        return entry
    }

    // MARK: - #52 Rollover landing

    @Test("#52 an autumn rollover re-dates carried-over plans from after today, never into the past")
    func autumnLandingIsNotInThePast() throws {
        let context = try makeContext()
        let store = makeStore()
        let current = store.current
        let viewModel = SchoolYearRolloverViewModel()
        // Closing out last year in autumn: the year rolled into is the one under way.
        viewModel.plan = RolloverPlan(
            effectiveDate: cal.date(byAdding: .day, value: -1, to: current.start) ?? current.start
        )
        #expect(viewModel.incomingYear(store: store).beginYear == current.beginYear)
        let today = AppCalendar.startOfDay(Date())

        let landing = viewModel.carryOverLandingDate(store: store, context: context)
        #expect(landing > today)
        #expect(landing >= current.start)

        // A date picked before today is moved up to the earliest allowed day.
        viewModel.plan.carryOverLanding = current.start
        #expect(viewModel.carryOverLandingDate(store: store, context: context) > today)
    }

    @Test("#52 guard: a spring rollover still lands on the incoming year's first open day")
    func springLandingIsTheIncomingStart() throws {
        let context = try makeContext()
        let store = makeStore()
        let current = store.current
        let viewModel = SchoolYearRolloverViewModel()
        // Closing out this year: the year rolled into starts after today.
        viewModel.plan = RolloverPlan(
            effectiveDate: cal.date(byAdding: .day, value: -1, to: current.end) ?? current.end
        )
        let incoming = viewModel.incomingYear(store: store)
        let landing = viewModel.carryOverLandingDate(store: store, context: context)
        #expect(landing == YearPlanPacing.schoolDay(onOrAfter: incoming.start, in: context))
    }

    // MARK: - #53 Closed-day count

    @Test("#53 the closed-day warning counts only planned entries from today on")
    func closedDayCountIsPlannedFromToday() throws {
        let context = try makeContext()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Rhombus")
        let today = AppCalendar.startOfDay(Date())
        let ahead = AppCalendar.addingDays(30, to: today)
        let behind = AppCalendar.addingDays(-30, to: today)
        closeSchool(on: ahead, in: context)
        closeSchool(on: behind, in: context)
        // The one Readjust can move.
        seedEntry(in: context, student: ora, lesson: lesson, plannedDate: ahead, order: 0)
        // Promoted: a real assignment, which Readjust leaves alone.
        seedEntry(in: context, student: ora, lesson: lesson, plannedDate: ahead, order: 1, status: .promoted)
        // Already past: not a target still ahead.
        seedEntry(in: context, student: ora, lesson: lesson, plannedDate: behind, order: 2)
        #expect(CoreDataTestHelpers.save(context))
        SchoolCalendarService.shared.invalidateCache()

        let viewModel = StudentYearPlanViewModel()
        viewModel.load(studentID: ora.id, context: context)
        #expect(viewModel.closedDayCount == 1)
    }

    // MARK: - #57 Re-dating after a closed day

    @Test("#57 an entry on a closed day and the next day's entry don't land on one day")
    func redateAfterClosedDayKeepsTwoDays() throws {
        let context = try makeContext()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Rhombus")
        // Tue Apr 14 2026 closed (a holiday the plan sat on), Wed Apr 15 open.
        closeSchool(on: day(2026, 4, 14), in: context)
        let first = seedEntry(in: context, student: ora, lesson: lesson, plannedDate: day(2026, 4, 14), order: 0)
        let second = seedEntry(in: context, student: ora, lesson: lesson, plannedDate: day(2026, 4, 15), order: 1)
        #expect(CoreDataTestHelpers.save(context))
        SchoolCalendarService.shared.invalidateCache()

        // Mon Sep 14 2026.
        YearPlanCarryOver.redate([first, second], landingOn: day(2026, 9, 14), in: context)
        #expect(first.plannedDate == day(2026, 9, 14))
        #expect(second.plannedDate == day(2026, 9, 15))
    }

    @Test("#57 guard: two targets that shared a day still share one")
    func redateSameDayStaysTogether() throws {
        let context = try makeContext()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Rhombus")
        let first = seedEntry(in: context, student: ora, lesson: lesson, plannedDate: day(2026, 4, 15), order: 0)
        let second = seedEntry(in: context, student: ora, lesson: lesson, plannedDate: day(2026, 4, 15), order: 1)
        let third = seedEntry(in: context, student: ora, lesson: lesson, plannedDate: day(2026, 4, 17), order: 2)
        #expect(CoreDataTestHelpers.save(context))
        SchoolCalendarService.shared.invalidateCache()

        YearPlanCarryOver.redate([first, second, third], landingOn: day(2026, 9, 14), in: context)
        #expect(first.plannedDate == day(2026, 9, 14))
        #expect(second.plannedDate == day(2026, 9, 14))
        // Wed → Fri is two school days.
        #expect(third.plannedDate == day(2026, 9, 16))
    }

    // MARK: - #59 Carried-over sweep

    @Test("#59 a failed sweep save changes nothing, stays on the choices and doesn't mark the year swept")
    func failedSweepSaveChangesNothing() throws {
        let key = UserDefaultsKeys.yearPlanCarryOverSweepYear
        let defaults = UserDefaults.standard
        let saved = defaults.object(forKey: key)
        defaults.removeObject(forKey: key)
        defer { defaults.set(saved, forKey: key) }

        let context = try makeContext()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Rhombus")
        let lastYear = YearPlanStaleness.previousSchoolYear()
        let entry = seedEntry(
            in: context, student: ora, lesson: lesson,
            plannedDate: AppCalendar.addingDays(40, to: lastYear.start)
        )
        #expect(CoreDataTestHelpers.save(context))

        let viewModel = CarriedOverPlanSweepViewModel()
        viewModel.load(context: context, showTestStudents: true, testStudentNames: "")
        #expect(viewModel.surveys.count == 1)
        viewModel.setChoice(.skip, for: try #require(ora.id))

        // Something else in the context that makes every save fail.
        let poison = CDNoteStudentLink(context: context)
        poison.setValue(nil, forKey: "noteID")
        viewModel.apply(context: context)

        #expect(viewModel.phase == .choose)
        #expect(entry.status == .planned)
        #expect(defaults.object(forKey: key) == nil)
        // The guide's other pending change is still there.
        #expect(!poison.isDeleted && poison.managedObjectContext != nil)
    }

    // MARK: - #47 Taking a child off a presentation

    @Test("#47 taking a child off offers to delete her own single-child row from this presentation")
    func retractionOffersHerOwnRow() throws {
        let context = try makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Commutative Law")
        let naomi = CoreDataTestHelpers.seedStudent(in: context, firstName: "Naomi", lastName: "Levin")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let assignment = PresentationFactory.makeDraft(lesson: lesson, students: [naomi, ora], context: context)
        assignment.markPresented(at: Date())
        #expect(CoreDataTestHelpers.save(context))
        let presentationID = try #require(assignment.id)
        let repository = WorkRepository(context: context)
        let rows = try [naomi, ora].map { student in
            let work = try repository.createWork(
                studentID: try #require(student.id), lessonID: try #require(lesson.id),
                title: "Define commutative property", kind: .followUpAssignment,
                presentationID: presentationID, saveImmediately: false
            )
            work.sourceContextType = .presentation
            work.sourceContextID = presentationID.uuidString
            return work
        }
        #expect(CoreDataTestHelpers.save(context))
        let naomiID = try #require(naomi.id)

        let plans = PresentationWorkRetraction.plans(forRemoving: [naomiID], from: assignment, in: context)
        #expect(plans.count == 1)
        #expect(plans.first?.steps.map(\.action) == [.deleteRow])
        #expect(plans.first?.steps.first?.work === rows[0])
        let lines = PresentationWorkRetraction.describe(plans, in: context)
        #expect(lines.count == 1)
        #expect(lines.first?.contains("deleted") == true)

        try PresentationWorkRetraction.apply(plans, in: context)
        #expect(CoreDataTestHelpers.save(context))
        #expect(rows[0].isDeleted || rows[0].managedObjectContext == nil)
        #expect(!rows[1].isDeleted)
    }

    @Test("#47 guard: a row made by another presentation is not offered")
    func retractionLeavesOtherPresentationsWork() throws {
        let context = try makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Commutative Law")
        let naomi = CoreDataTestHelpers.seedStudent(in: context, firstName: "Naomi", lastName: "Levin")
        let assignment = PresentationFactory.makeDraft(lesson: lesson, students: [naomi], context: context)
        assignment.markPresented(at: Date())
        let other = PresentationFactory.makeDraft(lesson: lesson, students: [naomi], context: context)
        other.markPresented(at: Date())
        #expect(CoreDataTestHelpers.save(context))
        _ = try WorkRepository(context: context).createWork(
            studentID: try #require(naomi.id), lessonID: try #require(lesson.id),
            title: "Define commutative property", kind: .followUpAssignment,
            presentationID: other.id, saveImmediately: false
        )
        #expect(CoreDataTestHelpers.save(context))

        let plans = PresentationWorkRetraction.plans(
            forRemoving: [try #require(naomi.id)], from: assignment, in: context
        )
        #expect(plans.isEmpty)
    }

    // MARK: - #51 Watching leaves out hidden test students

    @Test("#51 Watching's roster leaves out hidden test students")
    func watchingRosterHidesTestStudents() throws {
        let defaults = UserDefaults.standard
        let showKey = TestStudentsFilter.showKey
        let namesKey = TestStudentsFilter.namesKey
        let savedShow = defaults.object(forKey: showKey)
        let savedNames = defaults.object(forKey: namesKey)
        defaults.set(false, forKey: showKey)
        defaults.set("Testy McTest", forKey: namesKey)
        defer {
            defaults.set(savedShow, forKey: showKey)
            defaults.set(savedNames, forKey: namesKey)
        }

        let context = try makeContext()
        let real = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lovelace")
        let test = CoreDataTestHelpers.seedStudent(in: context, firstName: "Testy", lastName: "McTest")
        #expect(CoreDataTestHelpers.save(context))

        let ids = WatchListFetcher.enrolledIDs(in: context)
        #expect(ids.contains(try #require(real.id)))
        #expect(!ids.contains(try #require(test.id)))
    }

    // MARK: - Roster's next lesson

    @Test("The roster's next lesson is her earliest scheduled presentation's lesson")
    func rosterNextLessonFromSchedule() throws {
        let context = try makeContext()
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lovelace")
        let ben = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben", lastName: "Ito")
        let later = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game")
        let sooner = CoreDataTestHelpers.seedLesson(in: context, name: "Golden Beads")
        let given = CoreDataTestHelpers.seedLesson(in: context, name: "Bead Frame")
        let today = AppCalendar.startOfDay(Date())
        _ = PresentationFactory.makeScheduled(
            lesson: later, students: [ada], scheduledFor: AppCalendar.addingDays(5, to: today), context: context
        )
        _ = PresentationFactory.makeScheduled(
            lesson: sooner, students: [ada, ben], scheduledFor: AppCalendar.addingDays(2, to: today), context: context
        )
        let presented = PresentationFactory.makeDraft(lesson: given, students: [ada], context: context)
        presented.markPresented(at: AppCalendar.addingDays(-1, to: today))
        #expect(CoreDataTestHelpers.save(context))
        let students = context.safeFetch(CDFetchRequest(CDStudent.self))

        let viewModel = StudentsViewModel()
        viewModel.loadDataOnDemand(viewContext: context, calendar: cal, students: students)
        #expect(viewModel.signals(for: ada.id).nextLessonName == "Golden Beads")
        #expect(viewModel.signals(for: ben.id).nextLessonName == "Golden Beads")
    }
}
