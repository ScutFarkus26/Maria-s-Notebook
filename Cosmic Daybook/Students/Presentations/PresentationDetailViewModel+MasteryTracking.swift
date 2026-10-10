// PresentationDetailViewModel+MasteryTracking.swift
// CDLessonPresentation mastery state loading and updating for PresentationDetailViewModel.

import Foundation
import OSLog
import CoreData

extension PresentationDetailViewModel {

    // MARK: - Mastery State Loading (Static)

    /// Loads the "highest" mastery state from all students' CDLessonPresentation records.
    /// If any student has mastered, returns .proficient. Otherwise returns the highest state found.
    static func loadProficiencyState(
        lessonID: String,
        studentIDs: [String],
        viewContext: NSManagedObjectContext
    ) -> LessonPresentationState {
        guard !studentIDs.isEmpty, !lessonID.isEmpty else { return .presented }

        let allLessonPresentations: [CDLessonPresentation]
        do {
            let request = presentationsRequest(lessonID: lessonID, studentIDs: studentIDs)
            allLessonPresentations = try viewContext.fetch(request)
        } catch {
            Self.logger.warning("Failed to fetch CDLessonPresentation: \(error)")
            return .presented
        }
        let matching = allLessonPresentations.filter { lp in
            lp.lessonID == lessonID && studentIDs.contains(lp.studentID)
        }

        // Return the "highest" state found (mastered > readyForAssessment > practicing > presented)
        if matching.contains(where: { $0.state == .proficient }) {
            return .proficient
        } else if matching.contains(where: { $0.state == .readyForAssessment }) {
            return .readyForAssessment
        } else if matching.contains(where: { $0.state == .practicing }) {
            return .practicing
        }
        return .presented
    }

    /// The presentation records for one lesson and these students. Both
    /// attributes are Strings, so String arguments are the right type. This
    /// used to be a whole-table fetch filtered in memory by the same test; the
    /// in-memory filters that follow still apply, and store order is kept.
    static func presentationsRequest(lessonID: String, studentIDs: [String]) -> NSFetchRequest<CDLessonPresentation> {
        let req = CDFetchRequest(CDLessonPresentation.self)
        req.predicate = NSPredicate(format: "lessonID == %@ AND studentID IN %@", lessonID, studentIDs)
        return req
    }

    // MARK: - Mastery State Updating

    /// Gives every child a CDLessonPresentation record for this lesson, and,
    /// when the guide changed the group's mastery control, sets all of them
    /// to `state`. Otherwise existing records keep each child's own state and
    /// a missing one starts at `.presented`: the control shows the group's
    /// highest state, which is one child's, not everyone's.
    ///
    /// Every record a child has for the lesson changes together (a lesson
    /// given twice has two): changing only the first in store order left the
    /// latest one, which MCP and the record index read, saying otherwise. A
    /// missing record is made for this presentation and on its day (none for
    /// an undated one), so it follows the presentation when its lesson is
    /// changed or it is deleted, rather than standing alone dated today.
    func updateProficiencyState(
        lessonID: String,
        studentIDs: [String],
        state guideState: LessonPresentationState,
        guideChangedState: Bool
    ) {
        let state = guideChangedState ? guideState : .presented
        guard !studentIDs.isEmpty, !lessonID.isEmpty else { return }

        let allLessonPresentations = viewContext.safeFetch(
            Self.presentationsRequest(lessonID: lessonID, studentIDs: studentIDs)
        )

        for studentID in studentIDs {
            let existing = allLessonPresentations.filter {
                $0.lessonID == lessonID && $0.studentID == studentID && !$0.isDeleted
            }
            if !existing.isEmpty {
                guard guideChangedState else { continue }
                for row in existing {
                    Self.apply(state, to: row)
                }
            } else {
                let lp = CDLessonPresentation(context: viewContext)
                lp.studentID = studentID
                lp.lessonID = lessonID
                lp.presentationID = lessonAssignment.id?.uuidString
                lp.state = state
                lp.presentedAt = lessonAssignment.presentedAt
                lp.lastObservedAt = Date()
                lp.masteredAt = state == .proficient ? Date() : nil
            }
        }

        // If marking as mastered, check if track is now complete
        if guideChangedState, state == .proficient, let lesson = lessonAssignment.lesson {
            for studentID in studentIDs {
                SequenceTrackService.checkAndCompleteTrackIfNeeded(
                    lessonArea: lesson.area,
                    lessonSequence: lesson.sequence,
                    studentID: studentID,
                    context: viewContext,
                    saveCoordinator: saveCoordinator
                )
            }
        }
    }

    // MARK: - Sibling-Lesson Mastery Updates

    /// Updates the mastery state for a single (lesson, student) pair from the Sequence Recap.
    /// Used to change the status of past lessons in the group directly from the recap UI,
    /// independent of the current lesson assignment being edited. Persists immediately and
    /// recomputes the group recap so the badge + progress chip refresh.
    func updateSiblingLessonProficiencyState(
        lessonID: String,
        studentID: String,
        state: LessonPresentationState,
        lessons: [CDLesson],
        currentLesson: CDLesson?,
        students: [CDStudent]
    ) {
        guard !lessonID.isEmpty, !studentID.isEmpty else { return }

        let allLessonPresentations = viewContext.safeFetch(
            Self.presentationsRequest(lessonID: lessonID, studentIDs: [studentID])
        )

        // Every record she has for the lesson, as the detail view's control
        // does: a lesson given twice has two.
        let existing = allLessonPresentations.filter {
            $0.lessonID == lessonID && $0.studentID == studentID && !$0.isDeleted
        }
        if !existing.isEmpty {
            for row in existing {
                Self.apply(state, to: row)
            }
        } else {
            let lp = CDLessonPresentation(context: viewContext)
            lp.studentID = studentID
            lp.lessonID = lessonID
            lp.presentationID = nil
            lp.state = state
            lp.presentedAt = Date()
            lp.lastObservedAt = Date()
            lp.masteredAt = state == .proficient ? Date() : nil
        }

        // Track-completion check uses the sibling lesson's own area/sequence,
        // not the current lessonAssignment.lesson.
        if state == .proficient,
           let lesson = lessons.first(where: { $0.id?.uuidString == lessonID }) {
            SequenceTrackService.checkAndCompleteTrackIfNeeded(
                lessonArea: lesson.area,
                lessonSequence: lesson.sequence,
                studentID: studentID,
                context: viewContext,
                saveCoordinator: saveCoordinator
            )
        }

        _ = saveCoordinator.save(viewContext, reason: "Updating sibling lesson proficiency state")
        recomputeSequenceRecap(currentLesson: currentLesson, students: students)
    }

    /// The guide's mastery choice on one record: an existing mastered day is
    /// kept, and anything short of mastered clears it.
    static func apply(_ state: LessonPresentationState, to row: CDLessonPresentation) {
        row.state = state
        row.lastObservedAt = Date()
        if state == .proficient && row.masteredAt == nil {
            row.masteredAt = Date()
        } else if state != .proficient {
            row.masteredAt = nil
        }
    }
}
