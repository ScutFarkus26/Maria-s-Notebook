// WorkDataMaintenance.swift
// Best-effort data maintenance helpers for WorkModel.
// Behavior-preserving cleanup: comments and MARKs only.

import Foundation
import SwiftData

/// Non-critical maintenance utilities for keeping WorkModel data consistent.
/// These functions are idempotent and safe to call multiple times.
enum WorkDataMaintenance {
    // MARK: - Helpers
    /// Builds participant entities for the given student IDs and work item.
    /// Kept simple to help the compiler with type-checking.
    private static func makeParticipants(from studentIDs: [UUID], for work: WorkModel) -> [WorkParticipantEntity] {
        var result: [WorkParticipantEntity] = []
        result.reserveCapacity(studentIDs.count)
        for sid in studentIDs {
            let participant = WorkParticipantEntity(
                studentID: sid,
                completedAt: nil,
                work: work
            )
            result.append(participant)
        }
        return result
    }

    // MARK: - Backfill
    /// Backfill participants for any WorkModel that is missing them.
    /// If a WorkModel links to a StudentLesson, mirror its studentIDs into participants.
    /// Safe to call multiple times; it is idempotent.
    static func backfillParticipantsIfNeeded(using context: ModelContext) {
        do {
            // Fetch all WorkModel objects first
            let workFetch = FetchDescriptor<WorkModel>()
            let works: [WorkModel] = try context.fetch(workFetch)

            let lessonFetch: FetchDescriptor<StudentLesson> = FetchDescriptor<StudentLesson>()
            let allLessons: [StudentLesson] = try context.fetch(lessonFetch)
            var lessonsByID: [UUID: StudentLesson] = [:]
            lessonsByID.reserveCapacity(allLessons.count)
            for lesson in allLessons {
                lessonsByID[lesson.id] = lesson
            }

            var changed = false

            // Iterate and handle only those missing participants
            for w in works {
                let participantsOptional: [WorkParticipantEntity]? = w.participants
                var hasNoParticipants: Bool = true
                if let existing = participantsOptional {
                    hasNoParticipants = existing.isEmpty
                }
                guard hasNoParticipants else { continue }

                // If there's a linked StudentLesson, mirror its studentIDs
                guard let slID = w.studentLessonID else { continue }

                guard let sl = lessonsByID[slID] else { continue }

                // Build participants in simple, explicit steps
                let studentIDs: [UUID] = sl.studentIDs
                if studentIDs.isEmpty { continue }

                let newParticipants: [WorkParticipantEntity] = makeParticipants(from: studentIDs, for: w)
                if !newParticipants.isEmpty {
                    w.participants = newParticipants
                    changed = true
                }
            }

            if changed {
                try context.save()
            }
        } catch {
            // Non-fatal; maintenance best-effort
        }
    }
}

