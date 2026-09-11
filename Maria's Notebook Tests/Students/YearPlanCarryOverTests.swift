import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// Re-dating last year's intentions into this one has to keep the plan's
/// shape. A sequence spaced three school days apart is the guide's intention as
/// much as the lessons in it are, so the run is re-laid from a landing day with
/// the same school-day gaps — never piled onto one morning.
@Suite("Year Plan — Carry Over")
@MainActor
struct YearPlanCarryOverTests {

    private func makeContext() throws -> NSManagedObjectContext {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        SchoolCalendarService.shared.invalidateCache()
        return context
    }

    /// Fixed dates so nothing depends on the day the suite runs. April 2026's
    /// 14th, 17th and 24th are a Tuesday, a Friday and the Friday after.
    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = dayOfMonth
        return AppCalendar.shared.date(from: comps) ?? Date()
    }

    private var yearStart: Date {
        SchoolYear.boundaryDate(year: 2026, month: 9, day: 1, calendar: AppCalendar.shared)
    }

    private func closeSchool(
        from start: Date, through end: Date, in context: NSManagedObjectContext
    ) {
        var cursor = AppCalendar.startOfDay(start)
        let last = AppCalendar.startOfDay(end)
        while cursor <= last {
            let record = CDNonSchoolDay(context: context)
            record.date = cursor
            cursor = AppCalendar.addingDays(1, to: cursor)
        }
        CoreDataTestHelpers.save(context)
        SchoolCalendarService.shared.invalidateCache()
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

    // MARK: - Re-dating

    @Test("re-dating keeps the school days between targets")
    func redateKeepsSpacing() throws {
        let context = try makeContext()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Rhombus")

        // Tue Apr 14, Fri Apr 17 (3 school days later), Fri Apr 24 (5 more).
        let first = seedEntry(in: context, student: ora, lesson: lesson, plannedDate: day(2026, 4, 14), order: 0)
        let second = seedEntry(in: context, student: ora, lesson: lesson, plannedDate: day(2026, 4, 17), order: 1)
        let third = seedEntry(in: context, student: ora, lesson: lesson, plannedDate: day(2026, 4, 24), order: 2)
        CoreDataTestHelpers.save(context)

        // Tue Sep 15, 2026 — an ordinary open weekday.
        let landing = day(2026, 9, 15)
        let moved: Int = YearPlanCarryOver.redate([first, second, third], landingOn: landing, in: context)
        CoreDataTestHelpers.save(context)

        #expect(moved == 3)
        #expect(first.plannedDate == landing)
        let expectedSecond: Date = YearPlanPacing.advance(from: landing, bySchoolDays: 3, in: context)
        let expectedThird: Date = YearPlanPacing.advance(from: expectedSecond, bySchoolDays: 5, in: context)
        #expect(second.plannedDate == expectedSecond)
        #expect(third.plannedDate == expectedThird)
        // Order is preserved, strictly.
        #expect(landing < expectedSecond && expectedSecond < expectedThird)
    }

    @Test("a closed week is stepped over, not landed in")
    func redateStepsOverClosedDays() throws {
        let context = try makeContext()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Trapezoid")
        let entry = seedEntry(in: context, student: ora, lesson: lesson, plannedDate: day(2026, 4, 14))
        CoreDataTestHelpers.save(context)

        // The whole week of the landing day is closed.
        closeSchool(from: day(2026, 9, 14), through: day(2026, 9, 18), in: context)

        YearPlanCarryOver.redate([entry], landingOn: day(2026, 9, 15), in: context)
        CoreDataTestHelpers.save(context)

        let landed = try #require(entry.plannedDate)
        #expect(landed >= day(2026, 9, 19))
        #expect(!SchoolCalendarService.shared.isNonSchoolDaySync(landed, using: context))
    }

    @Test("two targets that shared a day still share one")
    func sameDayTargetsStayTogether() throws {
        let context = try makeContext()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Pentagon")
        let both = day(2026, 4, 14)
        let one = seedEntry(in: context, student: ora, lesson: lesson, plannedDate: both, order: 0)
        let two = seedEntry(in: context, student: ora, lesson: lesson, plannedDate: both, order: 1)
        CoreDataTestHelpers.save(context)

        let landing = day(2026, 9, 15)
        YearPlanCarryOver.redate([one, two], landingOn: landing, in: context)
        CoreDataTestHelpers.save(context)

        #expect(one.plannedDate == landing)
        #expect(two.plannedDate == landing)
    }

    // MARK: - Which entries are offered

    @Test("only carried-over, unanswered, still-planned entries are offered")
    func entriesExcludePromotedSkippedAndGiven() throws {
        let context = try makeContext()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let carriedLesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Decagon")
        let givenLesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Nonagon")

        let carried = seedEntry(
            in: context, student: ora, lesson: carriedLesson, plannedDate: day(2026, 4, 14)
        )
        // This year's target: not carried over.
        seedEntry(in: context, student: ora, lesson: carriedLesson, plannedDate: day(2026, 9, 30))
        // Promoted and skipped are the guide's own decisions, and stay.
        seedEntry(
            in: context, student: ora, lesson: carriedLesson,
            plannedDate: day(2026, 4, 15), status: .promoted
        )
        seedEntry(
            in: context, student: ora, lesson: carriedLesson,
            plannedDate: day(2026, 4, 16), status: .skipped
        )
        // An old target whose lesson has since been given is already answered.
        let answered = seedEntry(
            in: context, student: ora, lesson: givenLesson, plannedDate: day(2026, 4, 20)
        )
        let record = CDLessonPresentation(context: context)
        record.studentID = try #require(ora.id).uuidString
        record.lessonID = try #require(givenLesson.id).uuidString
        CoreDataTestHelpers.save(context)

        let found = YearPlanCarryOver.entries(
            for: try #require(ora.id), in: context, yearStart: yearStart
        )
        #expect(found.map(\.objectID) == [carried.objectID])
        #expect(!found.contains { $0.objectID == answered.objectID })
    }

    @Test("skipping counts the entries it retired and never deletes one")
    func skipRetiresWithoutDeleting() throws {
        let context = try makeContext()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Heptagon")
        let carried = seedEntry(in: context, student: ora, lesson: lesson, plannedDate: day(2026, 4, 14))
        let promoted = seedEntry(
            in: context, student: ora, lesson: lesson, plannedDate: day(2026, 4, 15), status: .promoted
        )
        CoreDataTestHelpers.save(context)

        let entries = YearPlanCarryOver.entries(
            for: try #require(ora.id), in: context, yearStart: yearStart
        )
        let skipped: Int = YearPlanCarryOver.skip(entries)
        CoreDataTestHelpers.save(context)

        #expect(skipped == 1)
        #expect(carried.status == .skipped)
        #expect(promoted.status == .promoted)
        let survivors: Int = context.safeFetch(CDFetchRequest(CDYearPlanEntry.self)).count
        #expect(survivors == 2)
    }

    // MARK: - Survey

    @Test("the survey names only children who have carried-over entries, with their date range")
    func surveyCountsAndRanges() throws {
        let context = try makeContext()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let maya = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Soto")
        let clean = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Octagon")

        seedEntry(in: context, student: ora, lesson: lesson, plannedDate: day(2026, 4, 14))
        seedEntry(in: context, student: ora, lesson: lesson, plannedDate: day(2026, 6, 2))
        seedEntry(in: context, student: maya, lesson: lesson, plannedDate: day(2026, 5, 5))
        seedEntry(in: context, student: clean, lesson: lesson, plannedDate: day(2026, 10, 5))
        CoreDataTestHelpers.save(context)

        let surveys: [YearPlanCarryOver.Survey] =
            YearPlanCarryOver.survey([ora, maya, clean], in: context, yearStart: yearStart)
        let names: [String] = surveys.map(\.name)
        #expect(names == ["Ora Pardo", "Maya Soto"])
        let oraRow = try #require(surveys.first)
        #expect(oraRow.count == 2)
        #expect(oraRow.earliest == day(2026, 4, 14))
        #expect(oraRow.latest == day(2026, 6, 2))
    }

    @Test("targets that land past the year end are counted, and the spacing is kept anyway")
    func overshootIsCounted() throws {
        let context = try makeContext()
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Icosagon")
        let first = seedEntry(in: context, student: ora, lesson: lesson, plannedDate: day(2026, 4, 14), order: 0)
        let second = seedEntry(in: context, student: ora, lesson: lesson, plannedDate: day(2026, 6, 2), order: 1)
        CoreDataTestHelpers.save(context)

        YearPlanCarryOver.redate([first, second], landingOn: day(2026, 9, 15), in: context)
        CoreDataTestHelpers.save(context)

        // Seven weeks of spacing survive the move — nothing is squeezed to fit
        // inside a year, which is the whole reason the overshoot is only
        // reported. The cutoff is pinned to where the run actually landed, so
        // the assertion does not depend on counting school days by hand.
        let firstLanded: Date = try #require(first.plannedDate)
        let secondLanded: Date = try #require(second.plannedDate)
        #expect(secondLanded > firstLanded)

        let justBefore: Date = AppCalendar.addingDays(-1, to: secondLanded)
        let overshot: Int = YearPlanCarryOver.landingAfterYearEnd([first, second], yearEnd: justBefore)
        #expect(overshot == 1)

        // The cutoff day itself counts as past the end: a target on the first
        // day of next year is next year's.
        let onTheDay: Int = YearPlanCarryOver.landingAfterYearEnd([first, second], yearEnd: secondLanded)
        #expect(onTheDay == 1)

        let wellAfter: Date = AppCalendar.addingDays(1, to: secondLanded)
        let none: Int = YearPlanCarryOver.landingAfterYearEnd([first, second], yearEnd: wellAfter)
        #expect(none == 0)
    }

    // MARK: - Rollover

    @Test("the rollover re-dates a staying child's carried-over plan and leaves a departing one to the cascade")
    func rolloverAppliesTheChoice() throws {
        let context = try makeContext()
        let staying = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let leaving = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maytal", lastName: "Meyer")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Hexagon")

        let hers = seedEntry(in: context, student: staying, lesson: lesson, plannedDate: day(2026, 4, 14))
        let departing = seedEntry(in: context, student: leaving, lesson: lesson, plannedDate: day(2026, 4, 14))
        CoreDataTestHelpers.save(context)

        var plan = RolloverPlan(effectiveDate: Date(), writeNotes: false)
        plan.outcomes[try #require(leaving.id)] = .withdraw
        plan.carryOver[try #require(staying.id)] = .redate
        // A choice for a departing child must not be acted on.
        plan.carryOver[try #require(leaving.id)] = .redate

        let roster: [CDStudent] = [staying, leaving]
        let landing = day(2026, 9, 15)
        let summary: RolloverSummary = RolloverService.summary(for: plan, students: roster, context: context)
        let toRedate: Int = summary.carriedOverToRedate
        let redateChildren: Int = summary.carriedOverRedateChildren
        #expect(toRedate == 1)
        #expect(redateChildren == 1)

        RolloverService.apply(
            plan, students: roster, incomingYearLabel: "2026–2027",
            carryOverLanding: landing, context: context
        )

        #expect(hers.plannedDate == landing)
        // The departure cascade wins: skipped, and never re-dated first.
        #expect(departing.status == .skipped)
        #expect(departing.plannedDate == day(2026, 4, 14))
    }
}
