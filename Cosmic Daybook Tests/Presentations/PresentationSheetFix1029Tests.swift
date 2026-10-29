import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Bug hunt 2026-10-29 of the presentation sheet's older code: How It Went
/// survives Edit Details, Earlier, Date Unknown keeps an absent child on the
/// plan, saving a given presentation again leaves its history alone, and Change
/// Lesson takes the open work and the saved name with it.
@Suite("Presentation sheet (bug hunt 2026-10-29)")
@MainActor
struct PresentationSheetFix1029Tests {

    private struct Room {
        let context: NSManagedObjectContext
        let ada: CDStudent
        let ben: CDStudent
        let addition: CDLesson
        let subtraction: CDLesson
    }

    private func makeRoom() throws -> Room {
        let context = try CoreDataTestHelpers.makeContext()
        let room = Room(
            context: context,
            ada: CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lane"),
            ben: CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben", lastName: "Ross"),
            addition: CoreDataTestHelpers.seedLesson(in: context, name: "Addition"),
            subtraction: CoreDataTestHelpers.seedLesson(in: context, name: "Subtraction")
        )
        #expect(CoreDataTestHelpers.save(context))
        return room
    }

    private func historyRow(for plan: CDLessonAssignment, in context: NSManagedObjectContext) throws -> CDLessonPresentation {
        let request = CDFetchRequest(CDLessonPresentation.self)
        request.predicate = NSPredicate(format: "presentationID == %@", try #require(plan.id).uuidString)
        return try #require(context.safeFetch(request).first)
    }

    private func viewModel(for plan: CDLessonAssignment, in room: Room) -> PresentationDetailViewModel {
        let coordinator = SaveCoordinator()
        coordinator.suppressAlerts = true
        return PresentationDetailViewModel(lessonAssignment: plan, viewContext: room.context, saveCoordinator: coordinator)
    }

    // MARK: - #1 Edit Details

    @Test("Going back to Edit Details keeps How It Went's choices; Undo forgets them")
    func editDetailsKeepsChoices() throws {
        let session = PresentationSession(presentationID: UUID())
        let adaID = UUID()
        session.showHowItWent()
        session.setDecision(.practice, for: adaID)
        session.showWho()

        #expect(session.hasOpenedHowItWent)
        #expect(session.decision(for: adaID) == .practice)

        session.forgetHowItWent()
        #expect(!session.hasOpenedHowItWent)
        #expect(session.decision(for: adaID) == .continueObserving)
    }

    // MARK: - #4 Earlier, Date Unknown

    @Test("Earlier, Date Unknown keeps a child not ticked as there on a plan of her own")
    func undatedKeepsAbsentChildOnPlan() throws {
        let room = try makeRoom()
        let plan = PresentationFactory.makeDraft(lesson: room.addition, students: [room.ada, room.ben], context: room.context)
        #expect(CoreDataTestHelpers.save(room.context))
        let benID = try #require(room.ben.id)
        let vm = viewModel(for: plan, in: room)

        vm.beginUndatedRecording(keepingOnPlan: [benID])
        vm.save(studentsAll: [room.ada, room.ben], lessons: [room.addition], lessonAssignmentsAll: [], calendar: AppCalendar.shared)

        #expect(plan.isPresented)
        #expect(plan.resolvedStudentIDs == [try #require(room.ada.id)])
        let others = room.context.safeFetch(CDFetchRequest(CDLessonAssignment.self)).filter { $0 != plan }
        #expect(others.count == 1)
        #expect(others.first?.resolvedStudentIDs == [benID])
        #expect(others.first?.isPresented == false)
        #expect(vm.undatedKeptOnPlan.isEmpty)
    }

    @Test("An Earlier, Date Unknown that never saved leaves the sheet not given")
    func cancelledUndatedTakesBack() throws {
        let room = try makeRoom()
        let plan = PresentationFactory.makeDraft(lesson: room.addition, students: [room.ada], context: room.context)
        #expect(CoreDataTestHelpers.save(room.context))
        let vm = viewModel(for: plan, in: room)
        vm.needsAnotherPresentation = true

        vm.beginUndatedRecording(keepingOnPlan: [])
        #expect(vm.isPresented)
        vm.takeBackUnsavedRecording()

        #expect(!vm.isPresented)
        #expect(vm.needsAnotherPresentation)
        #expect(!plan.isPresented)
    }

    // MARK: - #3 Saving a given presentation again

    @Test("Saving a given presentation again keeps a later observation and stays out of Following")
    func resaveLeavesHistoryAlone() throws {
        let room = try makeRoom()
        let plan = PresentationFactory.makeDraft(lesson: room.addition, students: [room.ada], context: room.context)
        let given = try CoreDataTestHelpers.day("2026-10-01")
        let observed = try CoreDataTestHelpers.day("2026-10-20")
        _ = try LifecycleService.recordPresentation(from: plan, presentedAt: given, modelContext: room.context)
        #expect(CoreDataTestHelpers.save(room.context))
        let row = try historyRow(for: plan, in: room.context)
        #expect(row.followUpActionRaw != nil)
        // An older row, from before Following, and a later Recall.
        row.followUpActionRaw = nil
        row.lastObservedAt = observed
        #expect(CoreDataTestHelpers.save(room.context))

        // What the sheet's Save does for a presentation already given.
        _ = try LifecycleService.recordPresentation(
            from: plan, presentedAt: given, modelContext: room.context, followExistingRows: false
        )
        #expect(row.lastObservedAt == observed)
        #expect(row.followUpActionRaw == nil)

        // A corrected date still moves it, past a later observation too.
        let later = try CoreDataTestHelpers.day("2026-10-25")
        _ = try LifecycleService.recordPresentation(from: plan, presentedAt: later, modelContext: room.context)
        #expect(row.presentedAt == later)
        #expect(row.lastObservedAt == later)
    }

    // MARK: - #7 and #8 Change Lesson

    @Test("Change Lesson on a given presentation moves its open work, retitled; finished work stays")
    func changeLessonMovesOpenWork() throws {
        let room = try makeRoom()
        let plan = PresentationFactory.makeDraft(lesson: room.addition, students: [room.ada], context: room.context)
        let given = try CoreDataTestHelpers.day("2026-10-01")
        _ = try LifecycleService.recordPresentation(from: plan, presentedAt: given, modelContext: room.context)
        let adaID = try #require(room.ada.id)
        let additionID = try #require(room.addition.id)
        let planID = try #require(plan.id)
        let repository = WorkRepository(context: room.context)
        let open = try repository.createWork(
            studentID: adaID, lessonID: additionID, title: "Practice: Addition",
            kind: .practiceLesson, presentationID: planID, saveImmediately: false
        )
        let done = try repository.createWork(
            studentID: adaID, lessonID: additionID, title: "Practice: Addition",
            kind: .followUpAssignment, presentationID: planID, saveImmediately: false
        )
        done.status = .mastered
        #expect(CoreDataTestHelpers.save(room.context))

        PresentationDetailActions().applyEditsToModel(
            lessonAssignment: plan,
            editingLessonID: try #require(room.subtraction.id),
            scheduledFor: nil,
            givenAt: given,
            isPresented: true,
            notes: "",
            needsAnotherPresentation: false,
            selectedStudentIDs: [adaID],
            studentsAll: [room.ada],
            lessons: [room.addition, room.subtraction],
            calendar: AppCalendar.shared
        )

        #expect(open.lessonID == room.subtraction.id?.uuidString)
        #expect(open.title == "Practice: Subtraction")
        #expect(done.lessonID == additionID.uuidString)
        #expect(done.title == "Practice: Addition")
    }

    @Test("Change Lesson on a plan that carries a saved name updates it")
    func changeLessonRefreshesSavedName() throws {
        let room = try makeRoom()
        let plan = PresentationFactory.makeDraft(lesson: room.addition, students: [room.ada], context: room.context)
        plan.lessonTitleSnapshot = "Addition"
        #expect(CoreDataTestHelpers.save(room.context))

        PresentationDetailActions().applyEditsToModel(
            lessonAssignment: plan,
            editingLessonID: try #require(room.subtraction.id),
            scheduledFor: nil,
            givenAt: nil,
            isPresented: false,
            notes: "",
            needsAnotherPresentation: false,
            selectedStudentIDs: [try #require(room.ada.id)],
            studentsAll: [room.ada],
            lessons: [room.addition, room.subtraction],
            calendar: AppCalendar.shared
        )

        #expect(plan.lessonTitleSnapshot == "Subtraction")
    }
}
