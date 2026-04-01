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
            allLessonPresentations = try viewContext.fetch(NSFetchRequest<CDLessonPresentation>(entityName: "LessonPresentation"))
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

        let allLessonPresentations = safeFetch(NSFetchRequest<CDLessonPresentation>(entityName: "LessonPresentation"))

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
                GroupTrackService.checkAndCompleteTrackIfNeeded(
                    lessonSubject: lesson.subject,
                    lessonGroup: lesson.group,
                    studentID: studentID,
                    context: viewContext,
                    saveCoordinator: saveCoordinator
                )
            }
        }
    }
}
