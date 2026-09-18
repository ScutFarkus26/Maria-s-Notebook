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
            let req = NSFetchRequest<CDLessonPresentation>(entityName: "LessonPresentation")
            allLessonPresentations = try viewContext.fetch(req)
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

    // MARK: - Mastery State Updating

    /// Updates the mastery state on all CDLessonPresentation records for this lesson and students.
    func updateProficiencyState(
        lessonID: String,
        studentIDs: [String],
        state: LessonPresentationState
    ) {
        guard !studentIDs.isEmpty, !lessonID.isEmpty else { return }

        let allLessonPresentations = viewContext.safeFetch(CDFetchRequest(CDLessonPresentation.self))

        for studentID in studentIDs {
            if let existing = allLessonPresentations.first(where: {
                $0.lessonID == lessonID && $0.studentID == studentID
            }) {
                existing.state = state
                existing.lastObservedAt = Date()
                if state == .proficient && existing.masteredAt == nil {
                    existing.masteredAt = Date()
                } else if state != .proficient {
                    existing.masteredAt = nil
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
        }

        // If marking as mastered, check if track is now complete
        if state == .proficient, let lesson = lessonAssignment.lesson {
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

        let allLessonPresentations = viewContext.safeFetch(CDFetchRequest(CDLessonPresentation.self))

        if let existing = allLessonPresentations.first(where: {
            $0.lessonID == lessonID && $0.studentID == studentID
        }) {
            existing.state = state
            existing.lastObservedAt = Date()
            if state == .proficient && existing.masteredAt == nil {
                existing.masteredAt = Date()
            } else if state != .proficient {
                existing.masteredAt = nil
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
}
