// PresentationQuickActionsSave.swift
// The Save of `PresentationQuickActionsView`, out of the view so its order is
// pinned by `PresentationQuickActionsSaveTests`.

import CoreData
import Foundation

/// What the quick-actions sheet's Save does: record the presentation when it
/// was given now and plan the next lesson in its group, apply the edits, plan
/// the lesson again when it needs another presentation, save, and close.
///
/// The two plans are optional, and each one's guards skip only that plan (no
/// next lesson, no children attached, or the same plan already open). The
/// save and the close always run: those guards once returned from the whole
/// Save, leaving a presentation marked given but unsaved, with the sheet open.
struct PresentationQuickActionsSave {
    let lessonAssignment: CDLessonAssignment
    let presentedNow: Bool
    let needsAnotherPresentation: Bool
    let catalog: LessonCatalog
    /// Every assignment, read when a plan checks for an open duplicate
    /// (the sheet's live query at that moment).
    let lessonAssignmentsAll: () -> [CDLessonAssignment]
    let studentsAll: [CDStudent]
    let viewContext: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator
    /// Runs after the next lesson in the group is planned and saved.
    let refreshPlanningInbox: () -> Void

    func run(close: () -> Void) {
        if presentedNow {
            recordPresentedNow()
            planNextLessonInGroup()
        }

        lessonAssignment.needsAnotherPresentation = needsAnotherPresentation

        // Ensure lesson relationship mirrors snapshot
        if let lessonIDUUID = UUID(uuidString: lessonAssignment.lessonID) {
            lessonAssignment.lesson = catalog.lesson(id: lessonIDUUID)
        }

        if needsAnotherPresentation {
            planAnotherPresentation()
        }

        saveCoordinator.save(viewContext, reason: "Saving quick actions")

        close()
    }

    private func recordPresentedNow() {
        let presentedDate = AppCalendar.startOfDay(Date())
        lessonAssignment.markPresented(at: presentedDate)
        do {
            _ = try LifecycleService.recordPresentation(
                from: lessonAssignment,
                presentedAt: presentedDate,
                modelContext: viewContext
            )
        } catch {
            // ignore
        }

        // Auto-enroll in track if lesson belongs to a track
        if let lesson = lessonAssignment.lesson {
            SequenceTrackService.autoEnrollInTrackIfNeeded(
                lessonArea: lesson.area,
                lessonSequence: lesson.sequence,
                studentIDs: lessonAssignment.studentIDs,
                context: viewContext,
                saveCoordinator: saveCoordinator
            )
        }
    }

    /// Phase 3: Auto-create next lesson in sequence when marking presented now.
    private func planNextLessonInGroup() {
        guard let lessonIDUUID = UUID(uuidString: lessonAssignment.lessonID),
              let current = catalog.lesson(id: lessonIDUUID) else { return }
        let currentArea = current.area.trimmed()
        let currentSequence = current.sequence.trimmed()
        guard !currentArea.isEmpty, !currentSequence.isEmpty else { return }
        let candidates = catalog.lessons(area: currentArea, sequence: currentSequence)
        guard let idx = candidates.firstIndex(where: { $0.id == current.id }), idx + 1 < candidates.count else {
            return
        }
        let next = candidates[idx + 1]
        guard let nextID = next.id else { return }
        let sameStudents = Set(lessonAssignment.resolvedStudentIDs)
        // Skip if there are no students attached
        guard !sameStudents.isEmpty else { return }
        let exists = lessonAssignmentsAll().contains { la in
            la.resolvedLessonID == nextID && Set(la.resolvedStudentIDs) == sameStudents && !la.isPresented
        }
        guard !exists else { return }
        let nextLesson = catalog.lesson(id: nextID)
        let nextStudents = studentsAll.filter { $0.id.map { sameStudents.contains($0) } ?? false }
        if let nextLesson {
            _ = PresentationFactory.makeDraft(
                lesson: nextLesson, students: nextStudents, context: viewContext
            )
        } else {
            _ = PresentationFactory.makeDraft(
                lessonID: nextID, studentIDs: Array(sameStudents), context: viewContext
            )
        }
        saveCoordinator.save(viewContext, reason: "Auto-creating next lesson")
        refreshPlanningInbox()
    }

    /// Plans the same lesson again for the same children.
    private func planAnotherPresentation() {
        // Skip creating follow-up if zero students
        guard !lessonAssignment.resolvedStudentIDs.isEmpty else { return }
        let sameStudents = Set(lessonAssignment.resolvedStudentIDs)
        let currentLessonID = lessonAssignment.resolvedLessonID
        let exists = lessonAssignmentsAll().contains { la in
            la.resolvedLessonID == currentLessonID && Set(la.resolvedStudentIDs) == sameStudents && !la.isPresented
        }
        guard !exists else { return }
        let currentLesson = UUID(uuidString: lessonAssignment.lessonID)
            .flatMap { lid in catalog.lesson(id: lid) }
        let currentStudents = studentsAll.filter { s in
            s.id.map { lessonAssignment.resolvedStudentIDs.contains($0) } ?? false
        }
        if let currentLesson {
            _ = PresentationFactory.makeDraft(
                lesson: currentLesson, students: currentStudents, context: viewContext
            )
        } else {
            _ = PresentationFactory.makeDraft(
                lessonID: currentLessonID, studentIDs: lessonAssignment.resolvedStudentIDs, context: viewContext
            )
        }
    }
}
