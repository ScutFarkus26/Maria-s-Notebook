// PresentationDetailViewModel+MasteryTracking.swift
// LessonPresentation mastery state loading and updating for PresentationDetailViewModel.

import Foundation
import OSLog
import SwiftData

extension PresentationDetailViewModel {

    // MARK: - Mastery State Loading (Static)

    /// Loads the "highest" mastery state from all students' LessonPresentation records.
    /// If any student has mastered, returns .proficient. Otherwise returns the highest state found.
    static func loadProficiencyState(
        lessonID: String,
        studentIDs: [String],
        modelContext: ModelContext
    ) -> LessonPresentationState {
        guard !studentIDs.isEmpty, !lessonID.isEmpty else { return .presented }

        let allLessonPresentations: [LessonPresentation]
        do {
            allLessonPresentations = try modelContext.fetch(FetchDescriptor<LessonPresentation>())
        } catch {
            Self.logger.warning("Failed to fetch LessonPresentation: \(error)")
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

    /// Updates the mastery state on all LessonPresentation records for this lesson and students.
    func updateProficiencyState(
        lessonID: String,
        studentIDs: [String],
        state: LessonPresentationState
    ) {
        guard !studentIDs.isEmpty, !lessonID.isEmpty else { return }

        let allLessonPresentations = safeFetch(FetchDescriptor<LessonPresentation>())

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
                let lp = LessonPresentation(
                    studentID: studentID,
                    lessonID: lessonID,
                    presentationID: nil,
                    state: state,
                    presentedAt: Date(),
                    lastObservedAt: Date(),
                    masteredAt: state == .proficient ? Date() : nil
                )
                modelContext.insert(lp)
            }
        }

        // If marking as mastered, check if track is now complete
        if state == .proficient, let lesson = lessonAssignment.lesson {
            for studentID in studentIDs {
                GroupTrackService.checkAndCompleteTrackIfNeeded(
                    lesson: lesson,
                    studentID: studentID,
                    modelContext: modelContext,
                    saveCoordinator: saveCoordinator
                )
            }
        }
    }
}
