import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// The ready queue's rules, one at a time.
///
/// A child belongs in it when the record says she was confirmed or mastered
/// on a lesson and the next lesson in the *same sub-area* is neither on her
/// record nor on a plan for her. Everything below is one of the ways that
/// sentence can fail.
@Suite("Ready For Next Engine")
@MainActor
struct ReadyForNextEngineTests {

    // MARK: - Fixture

    /// Three Math › Laws lessons in order, plus a Math › Fractions lesson
    /// that is *not* in the same sub-area however close it sits.
    private struct Library {
        let commutative: CDLesson
        let distributive: CDLesson
        let associative: CDLesson
        let equivalence: CDLesson
        var all: [CDLesson] { [commutative, distributive, associative, equivalence] }
    }

    private func makeContext() throws -> NSManagedObjectContext {
        try CoreDataTestHelpers.makeInMemoryStack().viewContext
    }

    private func seedLibrary(in context: NSManagedObjectContext) -> Library {
        func lesson(_ name: String, _ sequence: String, _ order: Int64) -> CDLesson {
            let lesson = CoreDataTestHelpers.seedLesson(
                in: context, name: name, area: "Math", sequence: sequence
            )
            lesson.orderInSequence = order
            return lesson
        }
        return Library(
            commutative: lesson("Commutative Law", "Laws", 10),
            distributive: lesson("Distributive Law", "Laws", 20),
            associative: lesson("Associative Law", "Laws", 30),
            equivalence: lesson("Equivalence", "Fractions", 20)
        )
    }

    /// Gives `lesson` to `student` and tags her confirmed, as capture does.
    @discardableResult
    private func confirm(
        _ student: CDStudent, on lesson: CDLesson, at day: Date,
        in context: NSManagedObjectContext
    ) throws -> CDLessonAssignment {
        let given = PresentationFactory.makePresented(
            lesson: lesson, students: [student], presentedAt: day, context: context
        )
        given.confirmStudent(try #require(student.id))
        return given
    }

    /// Runs the engine over one child and the whole library.
    private func items(
        for students: [CDStudent], library: Library, in context: NSManagedObjectContext
    ) throws -> [ReadyForNextItem] {
        #expect(CoreDataTestHelpers.save(context))
        let ids = try students.map { try #require($0.id).uuidString }
        let index = PresentationRecordIndex(students: Set(ids), in: context)
        return ReadyForNextEngine.items(
            studentIDs: ids, lessons: library.all, index: index, in: context
        )
    }

    private func day(_ text: String) throws -> Date {
        try #require(MCPNotebookTools.isoDay.date(from: text))
    }

    // MARK: - In the queue

    @Test("A confirmed lesson with an untouched successor puts her in the queue")
    func confirmedWithUntouchedSuccessor() throws {
        let context = try makeContext()
        let library = seedLibrary(in: context)
        let avital = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avital", lastName: "Beyderman")
        try confirm(avital, on: library.commutative, at: try day("2026-03-11"), in: context)

        let found = try items(for: [avital], library: library, in: context)

        #expect(found.count == 1)
        let item = try #require(found.first)
        #expect(item.studentID == (try #require(avital.id).uuidString))
        #expect(item.lessonID == (try #require(library.commutative.id).uuidString))
        #expect(item.nextLessonID == (try #require(library.distributive.id).uuidString))
        #expect(item.basis == .confirmed)
        #expect(item.tier == .ready)
        #expect(item.reasons.isEmpty)
        #expect(item.basisDate == AppCalendar.startOfDay(try day("2026-03-11")))
    }

    @Test("A mastery mark alone is basis enough, and beats a confirmation on the same lesson")
    func proficiencyBasisWinsOverConfirmation() throws {
        let context = try makeContext()
        let library = seedLibrary(in: context)
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Krinsky")
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")

        // Etty: mastered only — the lesson is on her record with no confirmation.
        PresentationFactory.makePresented(
            lesson: library.commutative, students: [etty], presentedAt: try day("2026-02-02"), context: context
        )
        let mark = CDLessonPresentation(context: context)
        mark.studentID = try #require(etty.id).uuidString
        mark.lessonID = try #require(library.commutative.id).uuidString
        mark.presentedAt = try day("2026-02-02")
        mark.masteredAt = try day("2026-03-01")

        // Ora: both marks. Mastery is the stronger claim, so it speaks.
        try confirm(ora, on: library.commutative, at: try day("2026-02-02"), in: context)
        let oraMark = CDLessonPresentation(context: context)
        oraMark.studentID = try #require(ora.id).uuidString
        oraMark.lessonID = try #require(library.commutative.id).uuidString
        oraMark.presentedAt = try day("2026-02-02")
        oraMark.masteredAt = try day("2026-03-05")

        let found = try items(for: [etty, ora], library: library, in: context)
        let distributiveID = try #require(library.distributive.id).uuidString

        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.basis == .mastered })
        #expect(found.allSatisfy { $0.nextLessonID == distributiveID })
    }

    // MARK: - Out of the queue

    @Test("A successor she has already been given is not waiting")
    func successorAlreadyPresented() throws {
        let context = try makeContext()
        let library = seedLibrary(in: context)
        let avital = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avital", lastName: "Beyderman")
        try confirm(avital, on: library.commutative, at: try day("2026-03-11"), in: context)
        PresentationFactory.makePresented(
            lesson: library.distributive, students: [avital],
            presentedAt: try day("2026-04-01"), context: context
        )

        #expect(try items(for: [avital], library: library, in: context).isEmpty)
    }

    @Test("A successor sitting in the planning list as an unpresented draft is not waiting")
    func successorOnADraft() throws {
        let context = try makeContext()
        let library = seedLibrary(in: context)
        let avital = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avital", lastName: "Beyderman")
        try confirm(avital, on: library.commutative, at: try day("2026-03-11"), in: context)
        PresentationFactory.makeDraft(lesson: library.distributive, students: [avital], context: context)

        #expect(try items(for: [avital], library: library, in: context).isEmpty)
    }

    @Test("A planned year-plan entry hides the successor; a skipped one does not")
    func successorInTheYearPlan() throws {
        let context = try makeContext()
        let library = seedLibrary(in: context)
        let avital = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avital", lastName: "Beyderman")
        try confirm(avital, on: library.commutative, at: try day("2026-03-11"), in: context)

        let entry = CDYearPlanEntry(context: context)
        entry.studentID = try #require(avital.id).uuidString
        entry.lessonID = try #require(library.distributive.id).uuidString
        entry.sequenceGroupKey = "Math::Laws"
        entry.statusRaw = YearPlanEntryStatus.planned.rawValue

        #expect(try items(for: [avital], library: library, in: context).isEmpty)

        // Skipped when she departs, or when the guide retires the intention:
        // the plan no longer speaks for her, so the record does again.
        entry.statusRaw = YearPlanEntryStatus.skipped.rawValue
        #expect(try items(for: [avital], library: library, in: context).count == 1)
    }

    @Test("A lesson last in its sub-area has no successor to wait for")
    func lastInSubArea() throws {
        let context = try makeContext()
        let library = seedLibrary(in: context)
        let avital = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avital", lastName: "Beyderman")
        try confirm(avital, on: library.associative, at: try day("2026-03-11"), in: context)

        #expect(try items(for: [avital], library: library, in: context).isEmpty)
    }

    @Test("The next lesson never comes from another sub-area")
    func neverCrossesSubAreas() throws {
        let context = try makeContext()
        let library = seedLibrary(in: context)
        let avital = CoreDataTestHelpers.seedStudent(in: context, firstName: "Avital", lastName: "Beyderman")
        // Fractions holds one lesson, filed at order 20 — the same number as
        // the Distributive Law. A sub-area of one has nothing after it.
        try confirm(avital, on: library.equivalence, at: try day("2026-03-11"), in: context)

        let found = try items(for: [avital], library: library, in: context)
        #expect(found.isEmpty)
    }

    // MARK: - The practice gate

    @Test("Open practice work on the lesson she had holds her at almost ready")
    func practiceGateHoldsHerAtAlmostReady() throws {
        let context = try makeContext()
        let library = seedLibrary(in: context)
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        try confirm(ora, on: library.commutative, at: try day("2026-03-11"), in: context)

        let settings = CDLessonSequenceSettings(context: context)
        settings.area = "Math"
        settings.sequence = "Laws"
        settings.requiresPractice = true
        settings.requiresTeacherConfirmation = false

        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Commutative Law practice",
            studentID: try #require(ora.id), lessonID: try #require(library.commutative.id)
        )
        work.statusRaw = "active"

        let found = try items(for: [ora], library: library, in: context)
        let item = try #require(found.first)
        #expect(item.tier == .almostReady)
        #expect(item.reasons == ["practice on Commutative Law not yet complete"])

        // Finished, and she is simply ready.
        work.statusRaw = "complete"
        let after = try #require(try items(for: [ora], library: library, in: context).first)
        #expect(after.tier == .ready)
        #expect(after.reasons.isEmpty)
    }

    @Test("A sub-area that does not require practice ignores open work")
    func practiceGateOffLeavesHerReady() throws {
        let context = try makeContext()
        let library = seedLibrary(in: context)
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        try confirm(ora, on: library.commutative, at: try day("2026-03-11"), in: context)

        let settings = CDLessonSequenceSettings(context: context)
        settings.area = "Math"
        settings.sequence = "Laws"
        settings.requiresPractice = false
        settings.requiresTeacherConfirmation = false

        let work = CoreDataTestHelpers.seedWorkModel(
            in: context, title: "Commutative Law practice",
            studentID: try #require(ora.id), lessonID: try #require(library.commutative.id)
        )
        work.statusRaw = "active"

        let item = try #require(try items(for: [ora], library: library, in: context).first)
        #expect(item.tier == .ready)
    }
}
