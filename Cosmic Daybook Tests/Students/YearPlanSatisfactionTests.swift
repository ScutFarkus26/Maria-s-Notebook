import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// An intention stops being an intention when the lesson is given.
///
/// Scheduling already promoted an entry out of the planned list, and
/// discarding the plan already put it back. Recording did neither, so a lesson
/// given without being scheduled first — the ordinary case, a child ready this
/// morning — left a planned entry behind with a target date sliding into the
/// past, reading as behind pace for the rest of the year.
///
/// The answer is derived rather than stored: `CDYearPlanEntry` is private-store
/// and `CDLessonPresentation` is shared-store, so a flag written at record time
/// would only ever close entries on the device that did the recording.
@Suite("Year Plan — Satisfaction")
@MainActor
struct YearPlanSatisfactionTests {

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    /// A day relative to today, never earlier than the first day of this
    /// school year: a target before that reads as *carried over from last
    /// year* rather than behind pace, and these tests are about behind pace.
    /// Without the clamp the suite goes red every early September.
    private func daysFromNow(_ days: Double) -> Date {
        let interval: TimeInterval = days * 86_400
        let seed = Date().addingTimeInterval(interval)
        return max(seed, YearPlanStaleness.currentYearStart())
    }

    @discardableResult
    private func seedEntry(
        in context: NSManagedObjectContext,
        student: CDStudent,
        lesson: CDLesson,
        status: YearPlanEntryStatus = .planned,
        promotedInto assignment: CDLessonAssignment? = nil,
        plannedDate: Date? = nil,
        orderInSequence: Int64 = 0
    ) -> CDYearPlanEntry {
        let entry = CDYearPlanEntry(context: context)
        entry.studentID = student.id?.uuidString ?? ""
        entry.lessonID = lesson.id?.uuidString ?? ""
        entry.plannedDate = plannedDate ?? daysFromNow(-3)
        entry.sequenceGroupKey = "Geometry::Polygons"
        entry.orderInSequence = orderInSequence
        entry.statusRaw = status.rawValue
        entry.promotedAssignmentID = assignment?.id?.uuidString
        return entry
    }

    @discardableResult
    private func record(
        _ assignment: CDLessonAssignment,
        in context: NSManagedObjectContext,
        at date: Date = Date()
    ) throws -> CDLessonAssignment {
        let recorded = try LifecycleService.recordPresentation(
            from: assignment, presentedAt: date, modelContext: context
        )
        CoreDataTestHelpers.save(context)
        return recorded
    }

    private func index(
        for entries: [CDYearPlanEntry], in context: NSManagedObjectContext
    ) -> YearPlanSatisfaction {
        YearPlanSatisfaction.index(for: entries, in: context)
    }

    // MARK: - The Reported Bug

    @Test("a lesson given without being scheduled answers every child's entry")
    func recordingSatisfiesPlannedEntries() throws {
        let context = try makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Second Polygon Presentation")
        let girls = ["Etty", "Tzofia", "Naomi"].map {
            CoreDataTestHelpers.seedStudent(in: context, firstName: $0, lastName: "Dechter")
        }
        let entries = girls.map { seedEntry(in: context, student: $0, lesson: lesson) }
        CoreDataTestHelpers.save(context)

        // `allSatisfy` is rethrows, and #expect will not swallow that, so the
        // reductions happen here and the macro only sees a Bool.
        let before = index(for: entries, in: context)
        let allBehindBefore: Bool = entries.allSatisfy { $0.isBehindPace(satisfiedBy: before) }
        #expect(allBehindBefore)

        let assignment = PresentationFactory.makeDraft(lesson: lesson, students: girls, context: context)
        try record(assignment, in: context)

        let after = index(for: entries, in: context)
        let allGiven: Bool = entries.allSatisfy { $0.isSatisfied(by: after) }
        let noneBehind: Bool = entries.allSatisfy { !$0.isBehindPace(satisfiedBy: after) }
        let allStillPlanned: Bool = entries.allSatisfy { $0.isPlanned }
        #expect(allGiven)
        #expect(noneBehind)
        // Still planned on the row — nothing was written to the entry itself.
        #expect(allStillPlanned)
    }

    @Test("a child added to the group on the day is answered with the rest")
    func recordingSatisfiesEntriesForChildrenAddedLate() throws {
        let context = try makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Nomenclature (Triangles)")
        let scheduled = CoreDataTestHelpers.seedStudent(in: context, firstName: "Leora", lastName: "Fleischmann")
        let joined = CoreDataTestHelpers.seedStudent(in: context, firstName: "Simma", lastName: "Zweig")

        let assignment = PresentationFactory.makeScheduled(
            lesson: lesson, students: [scheduled], scheduledFor: Date(), context: context
        )
        let promoted = seedEntry(
            in: context, student: scheduled, lesson: lesson, status: .promoted, promotedInto: assignment
        )
        let neverPromoted = seedEntry(in: context, student: joined, lesson: lesson)
        // The guide adds her to the group at the moment she gives it.
        assignment.studentIDs = [scheduled, joined].compactMap { $0.id?.uuidString }
        CoreDataTestHelpers.save(context)

        try record(assignment, in: context)

        let after = index(for: [promoted, neverPromoted], in: context)
        #expect(promoted.isSatisfied(by: after))
        #expect(neverPromoted.isSatisfied(by: after))
    }

    // MARK: - A Plan Written After The Fact

    @Test("a sequence added after a lesson was given starts from the next lesson")
    func aSequenceAddedAfterwardsMarksTheGivenLessonGiven() throws {
        let context = try makeContext()
        let girl = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Dechter")
        let given = CoreDataTestHelpers.seedLesson(
            in: context, name: "Second Polygon Presentation", area: "Geometry", sequence: "Polygons"
        )
        let next = CoreDataTestHelpers.seedLesson(
            in: context, name: "Nomenclature (General)", area: "Geometry", sequence: "Polygons"
        )

        // The lesson happens first, off-plan.
        let assignment = PresentationFactory.makeDraft(lesson: given, students: [girl], context: context)
        try record(assignment, in: context, at: daysFromNow(-9))

        // The guide lays out the rest of the sequence afterwards, and it
        // includes the lesson she has already given.
        let forGiven = seedEntry(
            in: context, student: girl, lesson: given, plannedDate: daysFromNow(-5), orderInSequence: 0
        )
        let forNext = seedEntry(
            in: context, student: girl, lesson: next, plannedDate: daysFromNow(-1), orderInSequence: 1
        )
        CoreDataTestHelpers.save(context)

        let satisfaction = index(for: [forGiven, forNext], in: context)
        #expect(forGiven.isSatisfied(by: satisfaction))
        #expect(!forGiven.isBehindPace(satisfiedBy: satisfaction))
        // The next lesson is untouched: still planned, and still behind pace,
        // because its target has passed and it has not been given.
        #expect(!forNext.isSatisfied(by: satisfaction))
        #expect(forNext.isBehindPace(satisfiedBy: satisfaction))
    }

    @Test("the calendar shows a satisfied entry as given and stops offering to move it")
    func satisfiedEntriesReadAsGiven() throws {
        let context = try makeContext()
        let girl = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "The Story of Pythagoras")
        let entry = seedEntry(in: context, student: girl, lesson: lesson)
        let assignment = PresentationFactory.makeDraft(lesson: lesson, students: [girl], context: context)
        try record(assignment, in: context)

        let satisfaction = index(for: [entry], in: context)
        let entryID: UUID = try #require(entry.id)
        let target: Date = try #require(entry.plannedDate)
        let item = YearPlanCalendarItem(
            id: entryID,
            lessonID: entry.lessonID,
            date: target,
            kind: .planEntry(entry),
            satisfaction: satisfaction
        )
        #expect(item.displayStatus == .given)
        #expect(item.isEditable == false)
    }

    // MARK: - Boundaries

    @Test("another child's entry and another lesson's entry are untouched")
    func satisfactionIsPerChildAndPerLesson() throws {
        let context = try makeContext()
        let taught = CoreDataTestHelpers.seedLesson(in: context, name: "Nomenclature (General)")
        let other = CoreDataTestHelpers.seedLesson(in: context, name: "Nomenclature of the Rhombus")
        let present = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Pardo")
        let absent = CoreDataTestHelpers.seedStudent(in: context, firstName: "Sarah", lastName: "Zakon")

        let mine = seedEntry(in: context, student: present, lesson: taught)
        let otherChild = seedEntry(in: context, student: absent, lesson: taught)
        let otherLesson = seedEntry(in: context, student: present, lesson: other)
        let assignment = PresentationFactory.makeDraft(lesson: taught, students: [present], context: context)
        try record(assignment, in: context)

        let satisfaction = index(for: [mine, otherChild, otherLesson], in: context)
        #expect(mine.isSatisfied(by: satisfaction))
        #expect(!otherChild.isSatisfied(by: satisfaction))
        #expect(!otherLesson.isSatisfied(by: satisfaction))
    }

    @Test("a skipped entry stays skipped and is never behind pace")
    func skippedEntriesAreLeftAlone() throws {
        let context = try makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Introduction to Large Bead Frame")
        let girl = CoreDataTestHelpers.seedStudent(in: context, firstName: "Zahava", lastName: "Wechsler")
        let entry = seedEntry(in: context, student: girl, lesson: lesson, status: .skipped)
        let assignment = PresentationFactory.makeDraft(lesson: lesson, students: [girl], context: context)
        try record(assignment, in: context)

        let satisfaction = index(for: [entry], in: context)
        #expect(entry.status == .skipped)
        #expect(!entry.isBehindPace(satisfiedBy: satisfaction))
    }

    @Test("an empty index satisfies nothing")
    func theEmptyIndexSatisfiesNothing() throws {
        let context = try makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: "Skip Counting")
        let girl = CoreDataTestHelpers.seedStudent(in: context, firstName: "Maya", lastName: "Singer")
        let entry = seedEntry(in: context, student: girl, lesson: lesson)
        CoreDataTestHelpers.save(context)

        #expect(!entry.isSatisfied(by: .none))
        #expect(entry.isBehindPace(satisfiedBy: .none))
    }
}
