import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// One child's Re-present stays hers (bug hunt 2026-10-12, #45): How It Went,
/// the command bar and MCP `record_presentation` (through
/// `CaptureFollowUpPersistence`) and the Plan sheet's "Plan a second pass"
/// (through `recordRepeatIntent`) file it the way meetings and recall checks
/// do — the shared flag only when she had the presentation alone, otherwise
/// her own row resolved as Re-present. And two observations for one child in
/// one filing flag the note they were written into, not a second copy (#51).
@Suite("Presentations fixes 2026-10-12: Re-present per child")
@MainActor
struct PresentationsRepresentFix1012Pr {

    private struct Classroom {
        let context: NSManagedObjectContext
        let lesson: CDLesson
        let ora: CDStudent
        let etty: CDStudent
    }

    private func seed() throws -> Classroom {
        let context = try CoreDataTestHelpers.makeContext()
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Checkerboard", area: "Math", sequence: "Multiplication"
        )
        let ora = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ora", lastName: "Levi")
        let etty = CoreDataTestHelpers.seedStudent(in: context, firstName: "Etty", lastName: "Klein")
        #expect(CoreDataTestHelpers.save(context))
        return Classroom(context: context, lesson: lesson, ora: ora, etty: etty)
    }

    private func presented(
        _ classroom: Classroom, to students: [CDStudent], on day: String = "2026-03-11"
    ) throws -> CDLessonAssignment {
        let assignment = PresentationFactory.makePresented(
            lesson: classroom.lesson, students: students,
            presentedAt: try CoreDataTestHelpers.day(day), context: classroom.context
        )
        #expect(CoreDataTestHelpers.save(classroom.context))
        return assignment
    }

    private func persistence(
        _ classroom: Classroom, for assignment: CDLessonAssignment
    ) throws -> CapturePersistenceContext {
        CapturePersistenceContext(
            lessonID: try #require(classroom.lesson.id),
            lessonName: classroom.lesson.name,
            presentationID: try #require(assignment.id),
            context: classroom.context
        )
    }

    private func entry(
        _ student: CDStudent, _ followUp: CaptureFollowUp, observation: String = "Lost the place borrowing."
    ) throws -> CaptureFollowUpPersistence.Entry {
        CaptureFollowUpPersistence.Entry(
            studentID: try #require(student.id),
            observation: observation,
            followUp: followUp,
            followUpDetail: ""
        )
    }

    /// Her `CDLessonPresentation` row on the presentation, if any.
    private func row(
        of student: CDStudent, on assignment: CDLessonAssignment, in context: NSManagedObjectContext
    ) throws -> CDLessonPresentation? {
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(
            format: "presentationID == %@ AND studentID == %@",
            try #require(assignment.id?.uuidString), try #require(student.id?.uuidString)
        )
        return context.safeFetch(request).first
    }

    // MARK: - The capture review (How It Went, the command bar, record_presentation)

    @Test("Re-present for one child of a group leaves the shared flag off and resolves her own row")
    func captureRepresentInAGroupIsHers() throws {
        let classroom = try seed()
        let group = try presented(classroom, to: [classroom.ora, classroom.etty])

        try CaptureFollowUpPersistence.persist(
            [try entry(classroom.ora, .represent)], assignment: group,
            lesson: classroom.lesson, persistence: try persistence(classroom, for: group)
        )
        #expect(CoreDataTestHelpers.save(classroom.context))

        let flagged: Bool = group.needsAnotherPresentation
        #expect(!flagged)
        let oraRow = try row(of: classroom.ora, on: group, in: classroom.context)
        let resolution: PresentationFollowUpResolution? = oraRow?.followUpResolution
        #expect(resolution == .supportOrRepresent)
        let ettyResolution: PresentationFollowUpResolution? =
            try row(of: classroom.etty, on: group, in: classroom.context)?.followUpResolution
        #expect(ettyResolution != .supportOrRepresent)
    }

    @Test("Re-present for a child who had the lesson alone sets the shared flag")
    func captureRepresentAloneFlagsThePresentation() throws {
        let classroom = try seed()
        let alone = try presented(classroom, to: [classroom.ora])

        try CaptureFollowUpPersistence.persist(
            [try entry(classroom.ora, .represent)], assignment: alone,
            lesson: classroom.lesson, persistence: try persistence(classroom, for: alone)
        )

        let flagged: Bool = alone.needsAnotherPresentation
        #expect(flagged)
    }

    // MARK: - "Plan a second pass" (recordRepeatIntent)

    @Test("A second pass for one child of a group leaves the group's record unflagged and resolves her row")
    func secondPassInAGroupIsHers() throws {
        let classroom = try seed()
        let group = try presented(classroom, to: [classroom.ora, classroom.etty])

        _ = try #require(PresentationPlanner.planDraft(
            lesson: classroom.lesson, students: [classroom.ora], purpose: .secondPass,
            plannedOn: try CoreDataTestHelpers.day("2026-04-02"), in: classroom.context
        ))
        #expect(CoreDataTestHelpers.save(classroom.context))

        let flagged: Bool = group.needsAnotherPresentation
        #expect(!flagged)
        let resolution: PresentationFollowUpResolution? =
            try row(of: classroom.ora, on: group, in: classroom.context)?.followUpResolution
        #expect(resolution == .supportOrRepresent)
        let ettyResolution: PresentationFollowUpResolution? =
            try row(of: classroom.etty, on: group, in: classroom.context)?.followUpResolution
        #expect(ettyResolution != .supportOrRepresent)
    }

    @Test("A second pass for a child who had the lesson alone flags her record")
    func secondPassAloneFlagsTheRecord() throws {
        let classroom = try seed()
        let alone = try presented(classroom, to: [classroom.ora])

        _ = try #require(PresentationPlanner.planDraft(
            lesson: classroom.lesson, students: [classroom.ora, classroom.etty], purpose: .secondPass,
            plannedOn: try CoreDataTestHelpers.day("2026-04-02"), in: classroom.context
        ))

        let flagged: Bool = alone.needsAnotherPresentation
        #expect(flagged)
    }

    // MARK: - Keep observing, twice for one child (#51)

    @Test("Two keep-observing entries for one child flag her one note, not a second copy")
    func twoObservationsFlagOneNote() throws {
        let classroom = try seed()
        let alone = try presented(classroom, to: [classroom.ora])
        let oraID = try #require(classroom.ora.id)
        // The way record_presentation writes them: one note per child, her
        // entries joined, then each entry's decision applied.
        let first = "Counted the squares by rows."
        let second = "Asked to do it again tomorrow."
        _ = try PresentationOutcomePersistenceService.persistObservations(
            groupObservation: "",
            studentObservations: [oraID: "\(first)\n\n\(second)"],
            studentIDs: [oraID],
            presentationID: alone.id,
            context: classroom.context
        )

        try CaptureFollowUpPersistence.persist(
            [
                try entry(classroom.ora, .continueObserving, observation: first),
                try entry(classroom.ora, .continueObserving, observation: second)
            ],
            assignment: alone, lesson: classroom.lesson, persistence: try persistence(classroom, for: alone)
        )
        #expect(CoreDataTestHelpers.save(classroom.context))

        let notes = (alone.unifiedNotes?.allObjects as? [CDNote]) ?? []
        let flagged = notes.filter(\.needsFollowUp)
        #expect(notes.count == 1)
        #expect(flagged.count == 1)
    }
}
