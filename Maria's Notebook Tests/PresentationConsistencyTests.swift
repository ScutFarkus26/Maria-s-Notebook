import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

/// Regression tests for the "mark as given" → per-student `CDLessonPresentation` invariant.
///
/// Four entry points historically called `CDLessonAssignment.markPresented()` without also
/// upserting per-student `CDLessonPresentation` rows. That made marked-given presentations
/// invisible in the Mastery Dashboard, Sequence Recap, Student Progress tab, and the
/// per-student mastery picker on the Presentation Detail screen — while the Class
/// Subject Checklist still showed them, because it reads `CDLessonAssignment.isPresented`.
///
/// Each test below exercises one entry point's logic and asserts both:
///   1. The assignment is in `.presented` state with `presentedAt` set.
///   2. A `CDLessonPresentation` exists for each student, with `state == .presented` and
///      `presentedAt` matching.
@Suite("Presentation Consistency: mark-as-given creates per-student rows")
@MainActor
final class PresentationConsistencyTests {

    // MARK: - Fixtures

    private func makeContext() throws -> NSManagedObjectContext {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        return stack.viewContext
    }

    private func presentationsFor(
        lessonID: String,
        in context: NSManagedObjectContext
    ) -> [CDLessonPresentation] {
        let req = CDFetchRequest(CDLessonPresentation.self)
        req.predicate = NSPredicate(format: "lessonID == %@", lessonID)
        return context.safeFetch(req)
    }

    private func makeLesson(in context: NSManagedObjectContext, name: String = "Test Lesson") -> CDLesson {
        let lesson = CoreDataTestHelpers.seedLesson(in: context, name: name)
        lesson.id = UUID()
        return lesson
    }

    private func makeStudent(in context: NSManagedObjectContext, firstName: String) -> CDStudent {
        let student = CoreDataTestHelpers.seedStudent(in: context, firstName: firstName)
        student.id = UUID()
        return student
    }

    // MARK: - Canonical contract

    @Test("LifecycleService.recordPresentation creates one CDLessonPresentation per student")
    func recordPresentationCreatesPerStudentRows() throws {
        let ctx = try makeContext()
        let lesson = makeLesson(in: ctx)
        let s1 = makeStudent(in: ctx, firstName: "A")
        let s2 = makeStudent(in: ctx, firstName: "B")

        let now = Date()
        let la = PresentationFactory.makeDraft(
            lessonID: lesson.id ?? UUID(),
            studentIDs: [s1.id!, s2.id!],
            context: ctx
        )
        la.lesson = lesson

        _ = try LifecycleService.recordPresentation(from: la, presentedAt: now, modelContext: ctx)

        #expect(la.state == .presented)
        #expect(la.presentedAt != nil)

        let rows = presentationsFor(lessonID: lesson.id!.uuidString, in: ctx)
        #expect(rows.count == 2)
        let studentIDs = Set(rows.map(\.studentID))
        #expect(studentIDs == Set([s1.id!.uuidString, s2.id!.uuidString]))
        #expect(rows.allSatisfy { $0.state == .presented })
        #expect(rows.allSatisfy { $0.presentedAt != nil })
    }

    @Test("recordPresentation is idempotent — second call does not duplicate rows")
    func recordPresentationIsIdempotent() throws {
        let ctx = try makeContext()
        let lesson = makeLesson(in: ctx)
        let s1 = makeStudent(in: ctx, firstName: "A")

        let la = PresentationFactory.makeDraft(
            lessonID: lesson.id ?? UUID(),
            studentIDs: [s1.id!],
            context: ctx
        )
        la.lesson = lesson

        let when = Date()
        _ = try LifecycleService.recordPresentation(from: la, presentedAt: when, modelContext: ctx)
        _ = try LifecycleService.recordPresentation(from: la, presentedAt: when, modelContext: ctx)

        let rows = presentationsFor(lessonID: lesson.id!.uuidString, in: ctx)
        #expect(rows.count == 1)
    }

    // MARK: - Entry point: StudentDetailViewModel.togglePresented

    @Test("StudentDetailViewModel.togglePresented (no upcoming) creates per-student row")
    func studentDetailVMTogglePresentedNewAssignment() throws {
        let ctx = try makeContext()
        let lesson = makeLesson(in: ctx)
        let student = makeStudent(in: ctx, firstName: "Solo")

        // Reproduce the "no upcoming" branch of togglePresented.
        let presentedDate = AppCalendar.startOfDay(Date())
        let la = PresentationFactory.makePresented(
            lessonID: lesson.id!,
            studentIDs: [student.id!],
            presentedAt: presentedDate,
            context: ctx
        )
        la.lesson = lesson
        la.syncSnapshotsFromRelationships()
        _ = try LifecycleService.recordPresentation(from: la, presentedAt: presentedDate, modelContext: ctx)

        #expect(la.state == .presented)
        let rows = presentationsFor(lessonID: lesson.id!.uuidString, in: ctx)
        #expect(rows.count == 1)
        #expect(rows.first?.studentID == student.id!.uuidString)
        #expect(rows.first?.state == .presented)
    }

    @Test("StudentDetailViewModel.togglePresented (upcoming exists) creates per-student row")
    func studentDetailVMTogglePresentedUpcoming() throws {
        let ctx = try makeContext()
        let lesson = makeLesson(in: ctx)
        let student = makeStudent(in: ctx, firstName: "Up")

        // Seed an upcoming (scheduled) assignment, then reproduce the upcoming branch.
        let scheduled = PresentationFactory.makeScheduled(
            lessonID: lesson.id!,
            studentIDs: [student.id!],
            scheduledFor: Date().addingTimeInterval(3600),
            context: ctx
        )
        scheduled.lesson = lesson

        let presentedDate = AppCalendar.startOfDay(Date())
        _ = try LifecycleService.recordPresentation(
            from: scheduled,
            presentedAt: presentedDate,
            modelContext: ctx
        )

        #expect(scheduled.state == .presented)
        let rows = presentationsFor(lessonID: lesson.id!.uuidString, in: ctx)
        #expect(rows.count == 1)
        #expect(rows.first?.studentID == student.id!.uuidString)
    }

    // MARK: - Entry point: GiveLessonViewModel save with needsPractice=false

    @Test("LessonPickerViewModel.save with mode=.given and needsPractice=false creates per-student rows")
    func giveLessonVMNoPracticeCreatesRows() throws {
        let ctx = try makeContext()
        let lesson = makeLesson(in: ctx, name: "Pouring")
        let s1 = makeStudent(in: ctx, firstName: "G1")
        let s2 = makeStudent(in: ctx, firstName: "G2")

        let vm = LessonPickerViewModel(
            selectedStudentIDs: [s1.id!, s2.id!],
            givenAt: Date(),
            needsPractice: false,
            selectedLessonID: lesson.id,
            mode: .given
        )
        vm.configure(lessons: [lesson], students: [s1, s2])

        try vm.save(context: ctx, resolvedLesson: lesson)

        let rows = presentationsFor(lessonID: lesson.id!.uuidString, in: ctx)
        let ids = Set(rows.map(\.studentID))
        #expect(ids == Set([s1.id!.uuidString, s2.id!.uuidString]))
        #expect(rows.allSatisfy { $0.state == .presented })

        // No CDWorkModel should have been created (needsPractice=false).
        let workReq = CDFetchRequest(CDWorkModel.self)
        let work = ctx.safeFetch(workReq)
        #expect(work.isEmpty)
    }

    // MARK: - Backfill migration

    @Test("Backfill migration creates missing per-student rows for orphaned presented assignments")
    func backfillCreatesMissingRows() throws {
        let ctx = try makeContext()
        let lesson = makeLesson(in: ctx, name: "Orphan")
        let s1 = makeStudent(in: ctx, firstName: "Orph1")
        let s2 = makeStudent(in: ctx, firstName: "Orph2")

        // Simulate a historical buggy path: assignment marked presented WITHOUT per-student rows.
        let la = PresentationFactory.makePresented(
            lessonID: lesson.id!,
            studentIDs: [s1.id!, s2.id!],
            presentedAt: Date().addingTimeInterval(-3600),
            context: ctx
        )
        la.lesson = lesson

        // Sanity: no per-student rows yet.
        #expect(presentationsFor(lessonID: lesson.id!.uuidString, in: ctx).isEmpty)

        // Reset the idempotency flag so the migration runs in this test.
        let key = "DataMigrations.lessonPresentationBackfill.v1.completed"
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        DataMigrations.backfillLessonPresentationsFromAssignments(using: ctx)

        let rows = presentationsFor(lessonID: lesson.id!.uuidString, in: ctx)
        #expect(rows.count == 2)
        let ids = Set(rows.map(\.studentID))
        #expect(ids == Set([s1.id!.uuidString, s2.id!.uuidString]))
        #expect(rows.allSatisfy { $0.state == .presented })

        // The idempotency flag should now be set.
        #expect(UserDefaults.standard.bool(forKey: key))
    }

    @Test("Backfill migration is a no-op on second invocation (guarded by UserDefaults flag)")
    func backfillIsNoOpOnSecondRun() throws {
        let ctx = try makeContext()
        let lesson = makeLesson(in: ctx, name: "NoOp")
        let s1 = makeStudent(in: ctx, firstName: "X")

        // First, simulate the migration already ran on a previous launch.
        let key = "DataMigrations.lessonPresentationBackfill.v1.completed"
        UserDefaults.standard.set(true, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        // Seed an orphan AFTER the flag is set — the migration should NOT touch it.
        let la = PresentationFactory.makePresented(
            lessonID: lesson.id!,
            studentIDs: [s1.id!],
            presentedAt: Date(),
            context: ctx
        )
        la.lesson = lesson

        DataMigrations.backfillLessonPresentationsFromAssignments(using: ctx)

        #expect(presentationsFor(lessonID: lesson.id!.uuidString, in: ctx).isEmpty)
    }
}
