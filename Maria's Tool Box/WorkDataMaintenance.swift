// WorkDataMaintenance.swift
// Best-effort data maintenance helpers for WorkModel.
// Behavior-preserving cleanup: comments and MARKs only.

import Foundation
import SwiftData

/// Non-critical maintenance utilities for keeping WorkModel data consistent.
/// These functions are idempotent and safe to call multiple times.
enum WorkDataMaintenance {
    // MARK: - Backfill
    /// Backfill participants for any WorkModel that is missing them.
    /// If a WorkModel links to a StudentLesson, mirror its studentIDs into participants.
    /// Safe to call multiple times; it is idempotent.
    static func backfillParticipantsIfNeeded(using context: ModelContext) {
        do {
            let works = try context.fetch(FetchDescriptor<WorkModel>())
            var changed = false
            for w in works where w.participants.isEmpty {
                if let slID = w.studentLessonID {
                    let descriptor = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == slID })
                    if let sl = try? context.fetch(descriptor).first {
                        let newParticipants = sl.studentIDs.map { sid in
                            WorkParticipantEntity(studentID: sid, completedAt: nil, work: w)
                        }
                        if !newParticipants.isEmpty {
                            w.participants = newParticipants
                            changed = true
                        }
                    }
                }
            }
            if changed { try context.save() }
        } catch {
            // Non-fatal; maintenance best-effort
        }
    }
}

