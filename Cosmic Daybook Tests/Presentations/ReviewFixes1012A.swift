import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Review findings on the 2026-10-12 presentation, work and year-plan fixes:
/// deleting her own generated row says what goes with it (#47), a failed
/// presentation save takes its work retraction back, Move All Forward keeps a
/// work's due date on its earliest open check-in (#49) and takes back a
/// failed save whole, the Lessons path's Plan reuses a child's waiting draft
/// (#32), and a keep-observing entry flags only the note it was written into
/// (#51).
@Suite("Review fixes 2026-10-12 (A)")
@MainActor
struct ReviewFixes1012A {

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

    /// One row for `student`, generated from `assignment` the way the
    /// follow-up service leaves it.
    private func generatedWork(
        for student: CDStudent, from assignment: CDLessonAssignment, in classroom: Classroom
    ) throws -> CDWorkModel {
        let presentationID = try #require(assignment.id)
        let work = try WorkRepository(context: classroom.context).createWork(
            studentID: try #require(student.id), lessonID: try #require(classroom.lesson.id),
            title: "Checkerboard practice", kind: .practiceLesson,
            presentationID: presentationID, saveImmediately: false
        )
        work.sourceContextType = .presentation
        work.sourceContextID = presentationID.uuidString
        return work
    }

    /// A row the save can't accept, inserted before the code under test runs,
    /// so its save fails and the poison stays the caller's own pending change.
    private func poison(_ context: NSManagedObjectContext) -> NSManagedObject {
        let poison = CDNoteStudentLink(context: context)
        poison.setValue(nil, forKey: "noteID")
        return poison
    }

    // MARK: - 1. Her own row's notes and check-ins (#47)

    @Test("Deleting her own generated row names the notes and check-ins that go with it")
    func ownRowDeletionCountsWhatGoes() throws {
        let classroom = try seed()
        let assignment = PresentationFactory.makeDraft(
            lesson: classroom.lesson, students: [classroom.ora], context: classroom.context
        )
        assignment.markPresented(at: Date())
        let work = try generatedWork(for: classroom.ora, from: assignment, in: classroom)
        let note = CoreDataTestHelpers.seedNote(in: classroom.context, body: "Filled the first row")
        note.work = work
        CDWorkCheckIn.make(for: work, on: Date(), in: classroom.context)
        CDWorkCheckIn.make(for: work, on: Date().addingTimeInterval(86_400), in: classroom.context)
        #expect(CoreDataTestHelpers.save(classroom.context))

        let plans = PresentationWorkRetraction.plans(
            forRemoving: [try #require(classroom.ora.id)], from: assignment, in: classroom.context
        )
        let lines = PresentationWorkRetraction.describe(plans, in: classroom.context)

        #expect(lines == ["Ora L’s “Checkerboard practice” is deleted, with its 1 note and 2 check-ins"])
    }

    // MARK: - 2. A failed presentation save takes the retraction back

    @Test("A failed save leaves the retracted work and the roster as they were")
    func failedSaveTakesRetractionBack() throws {
        let classroom = try seed()
        let assignment = PresentationFactory.makeDraft(
            lesson: classroom.lesson, students: [classroom.ora, classroom.etty], context: classroom.context
        )
        let ettysWork = try generatedWork(for: classroom.etty, from: assignment, in: classroom)
        #expect(CoreDataTestHelpers.save(classroom.context))
        let oraID = try #require(classroom.ora.id)
        let ettyID = try #require(classroom.etty.id)

        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        let viewModel = PresentationDetailViewModel(
            lessonAssignment: assignment, viewContext: classroom.context, saveCoordinator: coordinator
        )
        viewModel.selectedStudentIDs = [oraID]
        let plans = viewModel.workRetractionPlans()
        #expect(plans.count == 1)

        let blocker = poison(classroom.context)
        var finished = false
        viewModel.save(
            studentsAll: [classroom.ora, classroom.etty], lessons: [classroom.lesson],
            lessonAssignmentsAll: [assignment], calendar: AppCalendar.shared,
            retractingWork: plans
        ) { finished = true }

        #expect(!finished)
        #expect(!ettysWork.isDeleted)
        #expect(classroom.context.deletedObjects.isEmpty)
        #expect(Set(assignment.resolvedStudentIDs) == [oraID, ettyID])
        #expect(classroom.context.insertedObjects == [blocker])

        // With the cause gone, the same Save lands all of it.
        classroom.context.delete(blocker)
        viewModel.save(
            studentsAll: [classroom.ora, classroom.etty], lessons: [classroom.lesson],
            lessonAssignmentsAll: [assignment], calendar: AppCalendar.shared,
            retractingWork: viewModel.workRetractionPlans()
        ) { finished = true }
        #expect(finished)
        #expect(ettysWork.managedObjectContext == nil || ettysWork.isDeleted)
        #expect(Set(assignment.resolvedStudentIDs) == [oraID])
        #expect(!classroom.context.hasChanges)
    }

    // MARK: - 5. A work's due date after Move All Forward (#49)

    @Test("Move All Forward leaves a work due on its overdue check-in, not after it")
    func forwardShiftKeepsDueOnEarliestOpenCheckIn() throws {
        let classroom = try seed()
        let monday = try CoreDataTestHelpers.day("2026-06-08")
        let lastWeek = try CoreDataTestHelpers.day("2026-06-02")
        let tuesday = try CoreDataTestHelpers.day("2026-06-09")
        let work = CoreDataTestHelpers.seedWorkModel(in: classroom.context)
        work.dueAt = lastWeek
        let overdue = CDWorkCheckIn.make(for: work, on: lastWeek, in: classroom.context)
        let upcoming = CDWorkCheckIn.make(for: work, on: monday, in: classroom.context)
        #expect(CoreDataTestHelpers.save(classroom.context))

        CalendarForwardShiftService.moveForwardOneDay(
            in: classroom.context, calendar: AppCalendar.shared, from: monday,
            nextSchoolDay: { _ in tuesday }
        )

        #expect(overdue.date == lastWeek)
        #expect(upcoming.date == tuesday)
        #expect(work.dueAt == lastWeek)
    }

    // MARK: - 6. A failed Move All Forward save is taken back whole

    @Test("A failed Move All Forward save leaves nothing edited behind")
    func failedForwardShiftLeavesNothingDirty() throws {
        let classroom = try seed()
        let monday = try CoreDataTestHelpers.day("2026-06-08")
        let tuesday = try CoreDataTestHelpers.day("2026-06-09")
        let assignment = PresentationFactory.makeDraft(
            lesson: classroom.lesson, students: [classroom.ora], context: classroom.context
        )
        assignment.schedule(for: monday.addingTimeInterval(9 * 3_600), using: AppCalendar.shared)
        assignment.modifiedAt = try CoreDataTestHelpers.day("2026-06-01")
        let work = CoreDataTestHelpers.seedWorkModel(in: classroom.context)
        work.dueAt = monday
        let checkIn = CDWorkCheckIn.make(for: work, on: monday, in: classroom.context)
        #expect(CoreDataTestHelpers.save(classroom.context))
        let stamped = assignment.modifiedAt

        let result = CalendarForwardShiftService.moveForwardOneDayAndSave(
            in: classroom.context, calendar: AppCalendar.shared, from: monday,
            nextSchoolDay: { _ in tuesday }, persist: { false }
        )

        #expect(result == nil)
        #expect(assignment.modifiedAt == stamped)
        #expect(assignment.changedValues().isEmpty)
        #expect(checkIn.changedValues().isEmpty)
        #expect(work.changedValues().isEmpty)
    }

    // MARK: - 7. The Lessons path's Plan reuses a waiting draft (#32)

    @Test("Planning Ora and Etty from Lessons when Ora has a draft plans only Etty")
    func lessonsPlanLeavesOraOnHerDraft() throws {
        let classroom = try seed()
        let orasDraft = PresentationFactory.makeDraft(
            lesson: classroom.lesson, students: [classroom.ora], context: classroom.context
        )
        #expect(CoreDataTestHelpers.save(classroom.context))
        let oraID = try #require(classroom.ora.id)
        let ettyID = try #require(classroom.etty.id)

        let result = try #require(LessonsRootView.filePlan(
            for: classroom.lesson, studentIDs: [oraID, ettyID], purpose: nil, in: classroom.context
        ))

        #expect(result.isNew)
        #expect(result.plan != orasDraft)
        #expect(result.plan.resolvedStudentIDs == [ettyID])
        let waiting = PresentationPlanner.waitingPlans(
            lessonID: try #require(classroom.lesson.id), in: classroom.context
        )
        #expect(waiting.filter { $0.resolvedStudentIDs.contains(oraID) }.count == 1)
    }

    // MARK: - 9. Keep observing flags only the note it was written into (#51)

    @Test("A short keep-observing entry doesn't flag a longer note that happens to contain it")
    func keepObservingLeavesALongerNoteAlone() throws {
        let classroom = try seed()
        let assignment = PresentationFactory.makePresented(
            lesson: classroom.lesson, students: [classroom.ora],
            presentedAt: try CoreDataTestHelpers.day("2026-03-11"), context: classroom.context
        )
        let oraID = try #require(classroom.ora.id)
        let earlier = CoreDataTestHelpers.seedNote(
            in: classroom.context, body: "Asked if she could keep going. I said Yes. She did two more rows."
        )
        earlier.scope = .student(oraID)
        earlier.lessonAssignment = assignment
        #expect(CoreDataTestHelpers.save(classroom.context))

        let persistence = CapturePersistenceContext(
            lessonID: try #require(classroom.lesson.id),
            lessonName: classroom.lesson.name,
            presentationID: try #require(assignment.id),
            context: classroom.context
        )
        try CaptureFollowUpPersistence.persist(
            [CaptureFollowUpPersistence.Entry(
                studentID: oraID, observation: "Yes.", followUp: .continueObserving, followUpDetail: ""
            )],
            assignment: assignment, lesson: classroom.lesson, persistence: persistence
        )
        #expect(CoreDataTestHelpers.save(classroom.context))

        #expect(!earlier.needsFollowUp)
        let flagged = ((assignment.unifiedNotes?.allObjects as? [CDNote]) ?? []).filter(\.needsFollowUp)
        #expect(flagged.map(\.body) == ["Yes."])
    }

    @Test("A keep-observing entry joined into her note with another still flags that note")
    func keepObservingFlagsTheJoinedNote() throws {
        let classroom = try seed()
        let assignment = PresentationFactory.makePresented(
            lesson: classroom.lesson, students: [classroom.ora],
            presentedAt: try CoreDataTestHelpers.day("2026-03-11"), context: classroom.context
        )
        let oraID = try #require(classroom.ora.id)
        let joined = CoreDataTestHelpers.seedNote(in: classroom.context, body: "Counted by rows.\n\nYes.")
        joined.scope = .student(oraID)
        joined.lessonAssignment = assignment
        #expect(CoreDataTestHelpers.save(classroom.context))

        let persistence = CapturePersistenceContext(
            lessonID: try #require(classroom.lesson.id),
            lessonName: classroom.lesson.name,
            presentationID: try #require(assignment.id),
            context: classroom.context
        )
        try CaptureFollowUpPersistence.persist(
            [CaptureFollowUpPersistence.Entry(
                studentID: oraID, observation: "Yes.", followUp: .continueObserving, followUpDetail: ""
            )],
            assignment: assignment, lesson: classroom.lesson, persistence: persistence
        )
        #expect(CoreDataTestHelpers.save(classroom.context))

        #expect(joined.needsFollowUp)
        #expect((assignment.unifiedNotes?.count ?? 0) == 1)
    }
}
