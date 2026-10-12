import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-11, calendar, school year and Siri (#35, #36, #38, #39,
/// #41, #42). Serialized: the grade test moves the school-year start in the
/// shared defaults for a moment and puts it back.
@Suite("Calendar, school year and Siri (Fix1011 C)", .serialized)
@MainActor
struct CalendarSchoolYearSiriFix1011C {

    private let cal = AppCalendar.shared

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        cal.date(from: DateComponents(year: year, month: month, day: dayOfMonth)) ?? Date()
    }

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

    // MARK: - #35 Rollover default

    /// Six weeks into the year the year being closed out is the one that
    /// already ended: the default is the day before this year's first day,
    /// never today (which closed out the year still under way).
    @Test("#35 More than 30 days into the year, the default closes out last year")
    func rolloverDefaultsToLastYear() {
        let store = makeStore()
        let current = store.current
        let sixWeeksIn = cal.date(byAdding: .day, value: 46, to: current.start) ?? current.start
        let effective = SchoolYearRolloverViewModel.defaultEffectiveDate(today: sixWeeksIn, store: store)
        let dayBeforeStart = cal.date(byAdding: .day, value: -1, to: current.start) ?? current.start
        #expect(cal.isDate(effective, inSameDayAs: dayBeforeStart))

        let viewModel = SchoolYearRolloverViewModel()
        viewModel.plan = RolloverPlan(effectiveDate: effective)
        #expect(viewModel.outgoingYear(store: store).beginYear == current.beginYear - 1)
        #expect(viewModel.incomingYear(store: store).beginYear == current.beginYear)
    }

    @Test("#35 The closing stretch still defaults to this year's last day")
    func rolloverClosingStretchUnchanged() {
        let store = makeStore()
        let current = store.current
        let lateInYear = cal.date(byAdding: .day, value: -20, to: current.end) ?? current.end
        let effective = SchoolYearRolloverViewModel.defaultEffectiveDate(today: lateInYear, store: store)
        let lastDay = cal.date(byAdding: .day, value: -1, to: current.end) ?? current.end
        #expect(cal.isDate(effective, inSameDayAs: lastDay))
    }

    /// A year that ended long ago still rolls into the year under way, the
    /// store's current one, never into a year that hasn't come.
    @Test("#35 An older closing year rolls into the current year")
    func rolloverIncomingIsCurrentYear() {
        let store = makeStore()
        let current = store.current
        let twoYearsBack = cal.date(byAdding: .year, value: -2, to: current.start) ?? current.start
        let viewModel = SchoolYearRolloverViewModel()
        viewModel.plan = RolloverPlan(effectiveDate: twoYearsBack)
        #expect(viewModel.incomingYear(store: store, today: Date()).beginYear == current.beginYear)
    }

    /// A date inside the year still under way (outside its closing stretch)
    /// asks to confirm; last year's last day and this year's closing stretch
    /// don't.
    @Test("#35 A date inside the year under way asks to confirm")
    func rolloverConfirmsYearInProgress() {
        let store = makeStore()
        let current = store.current
        let today = cal.date(byAdding: .day, value: 46, to: current.start) ?? current.start
        let viewModel = SchoolYearRolloverViewModel()

        viewModel.plan = RolloverPlan(effectiveDate: today)
        #expect(viewModel.closesYearInProgress(store: store, today: today))
        #expect(viewModel.yearInProgressWarning(store: store, today: today) != nil)

        viewModel.plan = RolloverPlan(effectiveDate: current.start)
        #expect(viewModel.closesYearInProgress(store: store, today: today))

        viewModel.plan = RolloverPlan(
            effectiveDate: cal.date(byAdding: .day, value: -1, to: current.start) ?? current.start
        )
        #expect(!viewModel.closesYearInProgress(store: store, today: today))
        #expect(viewModel.yearInProgressWarning(store: store, today: today) == nil)

        viewModel.plan = RolloverPlan(
            effectiveDate: cal.date(byAdding: .day, value: -1, to: current.end) ?? current.end
        )
        #expect(!viewModel.closesYearInProgress(store: store, today: today))
    }

    // MARK: - #36 Add Sequence

    /// A skipped entry is the guide's "not this year", not a plan: re-adding
    /// the sequence schedules those lessons again, reusing the skipped row
    /// rather than leaving a gap or adding a second row for the same lesson.
    @Test("#36 Add Sequence schedules lessons whose entries were skipped")
    func addSequenceRevivesSkipped() async throws {
        let context = try makeContext()
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Lev")
        let lessons = (0..<3).map { index in
            let lesson = CoreDataTestHelpers.seedLesson(
                in: context, name: "Golden Beads \(index + 1)", area: "Math", sequence: "Golden Beads"
            )
            lesson.orderInSequence = Int64(index)
            return lesson
        }
        let studentID = try #require(student.id).uuidString
        for (index, lesson) in lessons.enumerated() {
            let entry = CDYearPlanEntry(context: context)
            entry.studentID = studentID
            entry.lessonID = try #require(lesson.id).uuidString
            entry.plannedDate = day(2026, 10, 5 + index)
            entry.status = index < 2 ? .skipped : .planned
        }
        #expect(CoreDataTestHelpers.save(context))

        let viewModel = AddSequenceViewModel()
        viewModel.selectedLesson = lessons[0]
        viewModel.startDate = day(2026, 11, 2)
        await viewModel.computePreview(student: student, context: context)

        #expect(viewModel.previewItems.map(\.alreadyExists) == [false, false, true])

        viewModel.scheduleAll(student: student, context: context)
        for (index, lesson) in lessons.enumerated() {
            let request = CDFetchRequest(CDYearPlanEntry.self)
            request.predicate = NSPredicate(
                format: "lessonID == %@ AND studentID == %@", try #require(lesson.id).uuidString, studentID
            )
            let entries = try context.fetch(request)
            #expect(entries.count == 1, "lesson \(index + 1) has one row")
            #expect(entries.first?.status == .planned, "lesson \(index + 1) is planned")
        }
    }

    // MARK: - #38 Grade cutoff

    /// The grade guidelines say "as of September 1st", Florida's rule. With the
    /// school year starting on August 25, a child born August 28 is six on
    /// September 1, so she is in 1st grade, not kindergarten.
    @Test("#38 Grades use September 1 whatever the school-year start")
    func gradeUsesSeptemberFirst() throws {
        let defaults = UserDefaults.standard
        let keys = [UserDefaultsKeys.schoolYearStartMonth, UserDefaultsKeys.schoolYearStartDay]
        let saved = keys.map { defaults.object(forKey: $0) }
        defer { for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) } }
        defaults.set(8, forKey: UserDefaultsKeys.schoolYearStartMonth)
        defaults.set(25, forKey: UserDefaultsKeys.schoolYearStartDay)

        let calendar = Calendar.current
        let birthday = try #require(calendar.date(from: DateComponents(year: 2020, month: 8, day: 28)))
        let october = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)))
        let firstWeek = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 27)))

        #expect(FloridaGradeCalculator.grade(for: birthday, referenceDate: october, calendar: calendar) == .grade(1))
        #expect(FloridaGradeCalculator.ageOnSchoolYearStart(
            birthday: birthday, referenceDate: october, calendar: calendar
        ) == 6)
        // In the school year's first week (after Aug 25, before Sep 1) the
        // cutoff is still this school year's September 1.
        #expect(FloridaGradeCalculator.grade(for: birthday, referenceDate: firstWeek, calendar: calendar) == .grade(1))
        // The attendance year start is untouched.
        let start = FloridaGradeCalculator.schoolYearStart(for: october, calendar: calendar)
        #expect(calendar.component(.month, from: start) == 8)
        #expect(calendar.component(.day, from: start) == 25)
    }

    // MARK: - #39 Spotlight

    /// Without a record of what was indexed before, everything of the type is
    /// removed once; with one, exactly the ids no longer current.
    @Test("#39 Spotlight removes ids that are no longer current")
    func spotlightRemovals() {
        let kept = UUID()
        let gone = UUID()
        #expect(SpotlightIndexer.removals(previous: nil, current: [kept]) == .everything)
        #expect(SpotlightIndexer.removals(
            previous: [kept.uuidString, gone.uuidString], current: [kept]
        ) == .ids([gone]))
        #expect(SpotlightIndexer.removals(previous: [kept.uuidString], current: [kept]) == .ids([]))
    }

    @Test("#39 Spotlight indexes only enrolled, visible students")
    func spotlightSnapshotRoster() throws {
        let context = try makeContext()
        let here = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Stone")
        let left = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Leah", lastName: "Gold", enrollmentStatus: .withdrawn
        )
        let test = CoreDataTestHelpers.seedStudent(in: context, firstName: "Lil Dan", lastName: "D")
        #expect(CoreDataTestHelpers.save(context))

        let snapshot = SpotlightIndexer.loadSnapshot(in: context, hiddenStudentNames: ["lil dan d"])
        let ids = Set(snapshot.studentIDs)
        #expect(ids.contains(try #require(here.id)))
        #expect(!ids.contains(try #require(left.id)))
        #expect(!ids.contains(try #require(test.id)))
    }

    // MARK: - #41 Calendar day notes

    /// Focus leaving a day commits only that day: a late focus-lost from the
    /// day she just left must not write the newly opened day's text into it.
    @Test("#41 A focus-lost commit only writes the day still open")
    func calendarNoteCommitIfOpen() throws {
        let context = try makeContext()
        let editor = CalendarNoteEditor()
        let first = CellID(year: 2026, month: 10, day: 6)
        let second = CellID(year: 2026, month: 10, day: 7)

        editor.beginEditing(first, currentText: "", notes: [:], in: context)
        editor.draft = "Picture day"
        editor.commitIfOpen(first, notes: [:], in: context)

        let request = CDFetchRequest(CDCalendarNote.self)
        var notes = try context.fetch(request)
        #expect(notes.count == 1)
        #expect(notes.first?.text == "Picture day")
        #expect(editor.editingCell == nil)

        editor.beginEditing(second, currentText: "", notes: [:], in: context)
        editor.draft = "Field trip"
        // The first day's field reports losing focus after the second opened.
        editor.commitIfOpen(first, notes: [:], in: context)
        #expect(editor.editingCell == second)
        notes = try context.fetch(request)
        #expect(notes.count == 1)
        #expect(notes.first?.text == "Picture day")
    }

    // MARK: - #42 School day toggle

    /// Two devices each marked the same weekday off: turning it back on
    /// clears both, in one tap.
    @Test("#42 Turning a day back on deletes every record for that day")
    func toggleDeletesWholeDay() async throws {
        let context = try makeContext()
        let monday = day(2026, 10, 12)
        for offset in [0, 3600] {
            let record = CDNonSchoolDay(context: context)
            record.date = monday.addingTimeInterval(TimeInterval(offset))
        }
        #expect(CoreDataTestHelpers.save(context))

        let isNonSchool = try await SchoolCalendarService.shared.toggleNonSchoolDay(monday, using: context)
        #expect(!isNonSchool)
        #expect(CoreDataTestHelpers.save(context))
        #expect(try context.count(for: CDFetchRequest(CDNonSchoolDay.self)) == 0)

        let saturday = day(2026, 10, 10)
        for _ in 0..<2 {
            let record = CDSchoolDayOverride(context: context)
            record.date = saturday
        }
        #expect(CoreDataTestHelpers.save(context))
        let weekendOff = try await SchoolCalendarService.shared.toggleNonSchoolDay(saturday, using: context)
        #expect(weekendOff)
        #expect(CoreDataTestHelpers.save(context))
        #expect(try context.count(for: CDFetchRequest(CDSchoolDayOverride.self)) == 0)
    }
}
