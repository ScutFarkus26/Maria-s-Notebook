import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The year-plan half of the departure cascade: a child who withdraws or
/// transfers comes off lessons still to be given (covered by
/// `StudentDeparturePlansTests`) *and* has her still-planned year-plan entries
/// marked skipped, so they stop accruing "behind pace" for a year she will not
/// be here for. Skipped, never deleted.
@Suite("Student Departure — Year Plan")
@MainActor
struct StudentDepartureYearPlanTests {

    /// Explicitly typed: the literal arithmetic is cheap here and costly inside
    /// a `#expect`, which the project caps at 100 ms of type-checking.
    ///
    /// A past seed is clamped forward to the first day of this school year: a
    /// target earlier than that is *carried over from last year*, not behind
    /// pace, and these tests are about the behind-pace half of the cascade.
    /// Without the clamp they would flip red every September.
    private func daysFromNow(_ days: Double) -> Date {
        let interval: TimeInterval = days * 86_400
        let seed = Date().addingTimeInterval(interval)
        return max(seed, YearPlanStaleness.currentYearStart())
    }

    /// A target genuinely from the school year that has ended.
    private func lastYear() -> Date {
        AppCalendar.addingDays(-10, to: YearPlanStaleness.currentYearStart())
    }

    private func allEntries(in context: NSManagedObjectContext) -> [CDYearPlanEntry] {
        context.safeFetch(CDFetchRequest(CDYearPlanEntry.self))
    }

    @discardableResult
    private func seedEntry(
        in context: NSManagedObjectContext,
        student: CDStudent,
        lesson: CDLesson,
        plannedDate: Date?,
        status: YearPlanEntryStatus = .planned
    ) -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = student.id?.uuidString ?? ""
        entry.lessonID = lesson.id?.uuidString ?? ""
        entry.plannedDate = plannedDate
        entry.sequenceGroupKey = "Geometry::Area"
        entry.statusRaw = status.rawValue
        return entry
    }

    @Test("planned entries are hers alone, soonest first, and exclude promoted ones")
    func plannedEntriesAreHersAndStillPlanned() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let naomi = CoreDataTestHelpers.seedStudent(in: context, firstName: "Naomi", lastName: "Levin")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Rhombus")

        let later = seedEntry(in: context, student: naomi, lesson: lesson, plannedDate: daysFromNow(20))
        let sooner = seedEntry(in: context, student: naomi, lesson: lesson, plannedDate: daysFromNow(2))
        seedEntry(in: context, student: naomi, lesson: lesson, plannedDate: Date(), status: .promoted)
        seedEntry(in: context, student: naomi, lesson: lesson, plannedDate: Date(), status: .skipped)
        seedEntry(in: context, student: ora, lesson: lesson, plannedDate: Date())
        CoreDataTestHelpers.save(context)

        let naomiID = try #require(naomi.id)
        let found: [NSManagedObjectID] = StudentDeparturePlans
            .plannedEntries(for: naomiID, in: context)
            .map(\.objectID)
        let expected: [NSManagedObjectID] = [sooner.objectID, later.objectID]
        #expect(found == expected)
    }

    @Test("skipping retires entries without deleting them")
    func skipRetiresWithoutDeleting() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let naomi = CoreDataTestHelpers.seedStudent(in: context, firstName: "Naomi", lastName: "Levin")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Trapezoid")
        let entry = seedEntry(in: context, student: naomi, lesson: lesson, plannedDate: Date())
        CoreDataTestHelpers.save(context)

        let naomiID = try #require(naomi.id)
        let planned = StudentDeparturePlans.plannedEntries(for: naomiID, in: context)
        let skipped: Int = StudentDeparturePlans.skip(entries: planned)
        CoreDataTestHelpers.save(context)

        let survivors: Int = allEntries(in: context).count
        #expect(skipped == 1)
        #expect(entry.status == .skipped)
        #expect(entry.isDeleted == false)
        #expect(survivors == 1)
    }

    @Test("withdrawing at rollover skips the year plan and stops it going behind pace")
    func rolloverSkipsYearPlanForDepartingChild() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let leaving = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maytal", lastName: "Meyer")
        let staying = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Decagon")

        // Two of hers already past their target date, one promoted onto the calendar.
        let behind = seedEntry(in: context, student: leaving, lesson: lesson, plannedDate: daysFromNow(-3))
        let alsoBehind = seedEntry(in: context, student: leaving, lesson: lesson, plannedDate: daysFromNow(-1))
        let promoted = seedEntry(
            in: context, student: leaving, lesson: lesson,
            plannedDate: daysFromNow(-5), status: .promoted
        )
        let orasEntry = seedEntry(in: context, student: staying, lesson: lesson, plannedDate: daysFromNow(-3))
        // One of hers from the school year that ended: carried over, and still
        // hers to be skipped when she leaves.
        let carried = seedEntry(in: context, student: leaving, lesson: lesson, plannedDate: lastYear())
        CoreDataTestHelpers.save(context)

        // No presentations exist here, so nothing is satisfied — behind pace
        // still means "planned, its target has passed, and that target was in
        // this school year".
        #expect(behind.isBehindPace(satisfiedBy: .none) || behind.plannedDate == YearPlanStaleness.currentYearStart())
        #expect(!behind.isCarriedOver())
        // Last year's target is carried over, and never behind pace.
        #expect(carried.isCarriedOver())
        #expect(!carried.isBehindPace(satisfiedBy: .none))

        var plan = RolloverPlan(effectiveDate: Date(), writeNotes: false)
        plan.outcomes[try #require(leaving.id)] = .withdraw
        let roster: [CDStudent] = [leaving, staying]

        let summary = RolloverService.summary(for: plan, students: roster, context: context)
        let counted: Int = summary.yearPlanEntriesForDeparting
        #expect(counted == 3)

        RolloverService.apply(
            plan, students: roster, incomingYearLabel: "2026–2027",
            carryOverLanding: Date(), context: context
        )

        let survivors: Int = allEntries(in: context).count
        #expect(leaving.isWithdrawn)
        #expect(behind.status == .skipped)
        #expect(alsoBehind.status == .skipped)
        // Her carried-over entry goes with the rest: she will not be here for it.
        #expect(carried.status == .skipped)
        // A skipped entry is no longer behind pace, because it is no longer planned.
        #expect(behind.isBehindPace(satisfiedBy: .none) == false)
        #expect(alsoBehind.isBehindPace(satisfiedBy: .none) == false)
        // The calendar keeps what it already owns, and other children are untouched.
        #expect(promoted.status == .promoted)
        #expect(orasEntry.status == .planned)
        // Skipped, never deleted.
        #expect(survivors == 5)
    }

    @Test("a departed child gets no new year-plan entries from an auto-populated sequence")
    func autoPopulateSkipsDepartedChildren() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let leaving = CoreDataTestHelpers.seedStudent(
            in: context, firstName: "Naomi", lastName: "Levin", enrollmentStatus: .withdrawn
        )
        let staying = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let first = CoreDataTestHelpers.seedLesson(
            in: context, name: "The Position of Two Lines", area: "Geometry", sequence: "Lines"
        )
        first.orderInSequence = 0
        let second = CoreDataTestHelpers.seedLesson(
            in: context, name: "Parallel Lines", area: "Geometry", sequence: "Lines"
        )
        second.orderInSequence = 1
        let assignment = PresentationFactory.makeDraft(
            lesson: first, students: [leaving, staying], context: context
        )
        CoreDataTestHelpers.save(context)

        await SequenceAutoPopulateService.autoPopulateSequence(
            for: assignment, scheduledDate: Date(), context: context
        )

        let leavingID: String = try #require(leaving.id).uuidString
        let stayingID: String = try #require(staying.id).uuidString
        let studentIDs: [String] = allEntries(in: context).map(\.studentID)
        #expect(studentIDs.contains(leavingID) == false)
        #expect(studentIDs.contains(stayingID))
    }
}
