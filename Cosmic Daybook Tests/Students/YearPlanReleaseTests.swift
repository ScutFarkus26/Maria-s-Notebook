import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Giving a lesson today retires the plan to give it on Thursday.
///
/// Whether the *intention* is answered is derived from the presentation record
/// and needs no write. A plan sitting on the calendar is not derived: a child
/// who receives the lesson this morning is still on Thursday's roster until
/// something takes her off it.
@Suite("Year Plan — Releasing Redundant Plans")
@MainActor
struct YearPlanReleaseTests {

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    private func daysFromNow(_ days: Double) -> Date {
        let interval: TimeInterval = days * 86_400
        return Date().addingTimeInterval(interval)
    }

    @discardableResult
    private func seedEntry(
        in context: NSManagedObjectContext,
        student: CDStudent,
        lesson: CDLesson,
        status: YearPlanEntryStatus = .planned,
        promotedInto assignment: CDLessonAssignment? = nil
    ) -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = student.id?.uuidString ?? ""
        entry.lessonID = lesson.id?.uuidString ?? ""
        entry.plannedDate = daysFromNow(3)
        entry.sequenceGroupKey = "Math::Preliminary"
        entry.statusRaw = status.rawValue
        entry.promotedAssignmentID = assignment?.id?.uuidString
        return entry
    }

    @discardableResult
    private func record(
        _ assignment: CDLessonAssignment, in context: NSManagedObjectContext
    ) throws -> CDLessonAssignment {
        let recorded = try LifecycleService.recordPresentation(
            from: assignment, presentedAt: Date(), modelContext: context
        )
        CoreDataTestHelpers.save(context)
        return recorded
    }

    @Test("a child who gets it early comes off the group she was pencilled into")
    func recordingTrimsTheOtherRoster() throws {
        let context = try makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Skip Counting")
        let early = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Singer")
        let thursdayGirl = CoreDataTestHelpers.seedStudent(in: context, firstName: "Toba", lastName: "Fleischmann")

        let thursday = PresentationFactory.makeScheduled(
            lesson: lesson, students: [early, thursdayGirl], scheduledFor: daysFromNow(3), context: context
        )
        seedEntry(in: context, student: early, lesson: lesson, status: .promoted, promotedInto: thursday)
        let hers = seedEntry(
            in: context, student: thursdayGirl, lesson: lesson, status: .promoted, promotedInto: thursday
        )
        let today = PresentationFactory.makeDraft(lesson: lesson, students: [early], context: context)
        CoreDataTestHelpers.save(context)

        try record(today, in: context)

        let thursdayGirlID: String = try #require(thursdayGirl.id).uuidString
        #expect(thursday.studentIDs == [thursdayGirlID])
        #expect(thursday.isDeleted == false)
        // Thursday still has a child on it, so her own entry still points at it.
        #expect(hers.isPromoted)
    }

    @Test("the plan is discarded when the last child comes off it")
    func recordingDiscardsAnEmptiedPlan() throws {
        let context = try makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game: Static Addition")
        let girl = CoreDataTestHelpers.seedStudent(in: context, firstName: "Baila", lastName: "Glauber")

        let thursday = PresentationFactory.makeScheduled(
            lesson: lesson, students: [girl], scheduledFor: daysFromNow(3), context: context
        )
        seedEntry(in: context, student: girl, lesson: lesson, status: .promoted, promotedInto: thursday)
        let today = PresentationFactory.makeDraft(lesson: lesson, students: [girl], context: context)
        CoreDataTestHelpers.save(context)

        try record(today, in: context)

        let plans = context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
        #expect(plans.map(\.objectID) == [today.objectID])
    }

    @Test("two children released from the same group empty it between them")
    func tworeleasesEmptyTheSameGroup() throws {
        let context = try makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Stamp Game Addition: Dynamic")
        let first = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avigail", lastName: "Greenbaum")
        let second = CoreDataTestHelpers.seedStudent(in: context, firstName: "Dalia", lastName: "Singer")

        let thursday = PresentationFactory.makeScheduled(
            lesson: lesson, students: [first, second], scheduledFor: daysFromNow(3), context: context
        )
        seedEntry(in: context, student: first, lesson: lesson, status: .promoted, promotedInto: thursday)
        seedEntry(in: context, student: second, lesson: lesson, status: .promoted, promotedInto: thursday)
        let today = PresentationFactory.makeDraft(
            lesson: lesson, students: [first, second], context: context
        )
        CoreDataTestHelpers.save(context)

        try record(today, in: context)

        let plans = context.safeFetch(CDFetchRequest(CDLessonAssignment.self))
        #expect(plans.map(\.objectID) == [today.objectID])
    }

    @Test("a presentation already given is history and keeps its roster")
    func aGivenPresentationIsLeftAlone() throws {
        let context = try makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Story of Pythagoras")
        let girl = CoreDataTestHelpers.seedStudent(in: context, firstName: "Dalia", lastName: "Singer")

        let given = PresentationFactory.makePresented(
            lesson: lesson, students: [girl], presentedAt: daysFromNow(-30), context: context
        )
        seedEntry(in: context, student: girl, lesson: lesson, status: .promoted, promotedInto: given)
        let again = PresentationFactory.makeDraft(lesson: lesson, students: [girl], context: context)
        CoreDataTestHelpers.save(context)

        try record(again, in: context)

        let girlID: String = try #require(girl.id).uuidString
        #expect(given.isDeleted == false)
        #expect(given.studentIDs == [girlID])
    }

    @Test("a group the guide assembled by hand is hers to change")
    func aPlanNoEntryPointsAtIsLeftAlone() throws {
        let context = try makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Nomenclature of the Rhombus")
        let girl = CoreDataTestHelpers.seedStudent(in: context, firstName: "Tiferet", lastName: "Pardo")

        // Scheduled, but no year-plan entry names it.
        let thursday = PresentationFactory.makeScheduled(
            lesson: lesson, students: [girl], scheduledFor: daysFromNow(3), context: context
        )
        let today = PresentationFactory.makeDraft(lesson: lesson, students: [girl], context: context)
        CoreDataTestHelpers.save(context)

        try record(today, in: context)

        let girlID: String = try #require(girl.id).uuidString
        #expect(thursday.isDeleted == false)
        #expect(thursday.studentIDs == [girlID])
    }

    @Test("running it again releases nobody")
    func releaseIsIdempotent() throws {
        let context = try makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Concept of a Polygon")
        let girl = CoreDataTestHelpers.seedStudent(in: context, firstName: "Lucy", lastName: "Tribuch")
        let thursday = PresentationFactory.makeScheduled(
            lesson: lesson, students: [girl], scheduledFor: daysFromNow(3), context: context
        )
        seedEntry(in: context, student: girl, lesson: lesson, status: .promoted, promotedInto: thursday)
        let today = PresentationFactory.makeDraft(lesson: lesson, students: [girl], context: context)
        CoreDataTestHelpers.save(context)

        try record(today, in: context)
        let second = YearPlanReleaseService.releaseRedundantPlans(after: today, in: context)

        #expect(second == YearPlanReleaseService.Outcome())
    }
}
