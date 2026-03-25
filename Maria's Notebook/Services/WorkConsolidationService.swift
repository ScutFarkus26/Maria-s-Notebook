import Foundation
import SwiftData

/// Service for consolidating duplicate WorkModel records.
/// Duplicates are identified by matching title, studentLessonID, and workType.
@MainActor
struct WorkConsolidationService {
    let context: ModelContext

    struct ConsolidationResult {
        let groupsConsolidated: Int
        let totalMerged: Int
        let errors: [String]
    }

    /// Consolidates duplicate works in the database.
    func consolidateDuplicates() -> ConsolidationResult {
        var groupsConsolidated = 0
        var totalMerged = 0
        var errors: [String] = []

        let descriptor = FetchDescriptor<WorkModel>()
        let allWorks = context.safeFetch(descriptor)

        guard !allWorks.isEmpty else {
            return ConsolidationResult(groupsConsolidated: 0, totalMerged: 0, errors: [])
        }

        let groups = allWorks.grouped { work -> String in
            let title = work.title.trimmed()
            let studentLessonID = work.studentLessonID?.uuidString ?? "nil"
            let workKind = (work.kind ?? .research).rawValue
            return "\(title)|\(studentLessonID)|\(workKind)"
        }

        for (_, group) in groups {
            guard group.count > 1 else { continue }

            groupsConsolidated += 1
            totalMerged += (group.count - 1)

            guard let canonical = group.min(by: { $0.createdAt < $1.createdAt }) else {
                errors.append("Failed to find canonical work in group")
                continue
            }

            let duplicates = group.filter { $0.id != canonical.id }
            mergeParticipants(into: canonical, from: duplicates)
            mergeNotes(into: canonical, from: duplicates)
            mergeCheckInsAndUnifiedNotes(into: canonical, from: duplicates)
            mergeDates(into: canonical, from: duplicates)
            mergeCompletionStatus(into: canonical, from: duplicates)

            for duplicate in duplicates {
                context.delete(duplicate)
            }
        }

        do {
            try context.save()
        } catch {
            errors.append("Failed to save changes: \(error.localizedDescription)")
        }

        return ConsolidationResult(groupsConsolidated: groupsConsolidated, totalMerged: totalMerged, errors: errors)
    }

    // MARK: - Merge Helpers

    /// Merges participants from duplicates into the canonical work, preserving earliest completion dates.
    private func mergeParticipants(into canonical: WorkModel, from duplicates: [WorkModel]) {
        var allParticipantIDs = Set<String>()
        for work in [canonical] + duplicates {
            if let participants = work.participants {
                for participant in participants {
                    allParticipantIDs.insert(participant.studentID)
                }
            }
        }
        guard !allParticipantIDs.isEmpty else { return }

        let existingParticipantIDs = Set((canonical.participants ?? []).map(\.studentID))

        for participantID in allParticipantIDs {
            if !existingParticipantIDs.contains(participantID) {
                addNewParticipant(participantID, into: canonical, from: duplicates)
            } else {
                mergeExistingParticipantDates(participantID, canonical: canonical, duplicates: duplicates)
            }
        }
    }

    private func addNewParticipant(
        _ participantID: String, into canonical: WorkModel, from duplicates: [WorkModel]
    ) {
        guard let studentUUID = UUID(uuidString: participantID) else { return }

        // Collect earliest completion date from all duplicates
        var completedAt: Date?
        for duplicate in duplicates {
            if let dupParticipants = duplicate.participants,
               let dupParticipant = dupParticipants.first(where: { $0.studentID == participantID }),
               let dupCompletedAt = dupParticipant.completedAt {
                if let existing = completedAt {
                    completedAt = min(existing, dupCompletedAt)
                } else {
                    completedAt = dupCompletedAt
                }
            }
        }

        let newParticipant = WorkParticipantEntity(
            studentID: studentUUID, completedAt: completedAt, work: canonical
        )
        if canonical.participants == nil { canonical.participants = [] }
        canonical.participants?.append(newParticipant)
    }

    private func mergeExistingParticipantDates(
        _ participantID: String, canonical: WorkModel, duplicates: [WorkModel]
    ) {
        let canonicalParts = canonical.participants ?? []
        guard let existingParticipant = canonicalParts.first(
            where: { $0.studentID == participantID }
        ) else { return }

        for duplicate in duplicates {
            if let dupParticipants = duplicate.participants,
               let dupParticipant = dupParticipants.first(where: { $0.studentID == participantID }),
               let dupCompletedAt = dupParticipant.completedAt {
                if let existingCompletedAt = existingParticipant.completedAt {
                    if dupCompletedAt < existingCompletedAt {
                        existingParticipant.completedAt = dupCompletedAt
                    }
                } else {
                    existingParticipant.completedAt = dupCompletedAt
                }
            }
        }
    }

    /// Merges note text from duplicates into the canonical work.
    private func mergeNotes(into canonical: WorkModel, from duplicates: [WorkModel]) {
        let canonicalNoteText = canonical.latestUnifiedNoteText.trimmed()
        if canonicalNoteText.isEmpty {
            // Use first non-empty note from duplicates
            for duplicate in duplicates {
                let dupNotes = duplicate.latestUnifiedNoteText.trimmed()
                if !dupNotes.isEmpty {
                    canonical.setLegacyNoteText(dupNotes, in: context)
                    break
                }
            }
        } else {
            // Append non-empty, non-duplicate notes
            var combinedNotes = canonicalNoteText
            for duplicate in duplicates {
                let dupNotes = duplicate.latestUnifiedNoteText.trimmed()
                if !dupNotes.isEmpty && !combinedNotes.contains(dupNotes) {
                    if !combinedNotes.isEmpty { combinedNotes += "\n\n" }
                    combinedNotes += dupNotes
                }
            }
            if combinedNotes != canonicalNoteText {
                canonical.setLegacyNoteText(combinedNotes, in: context)
            }
        }
    }

    /// Re-parents check-ins and unified notes from duplicates to the canonical work.
    private func mergeCheckInsAndUnifiedNotes(into canonical: WorkModel, from duplicates: [WorkModel]) {
        for duplicate in duplicates {
            if let dupCheckIns = duplicate.checkIns {
                if canonical.checkIns == nil { canonical.checkIns = [] }
                for checkIn in dupCheckIns {
                    checkIn.work = canonical
                    canonical.checkIns?.append(checkIn)
                }
            }
        }

        let notesToMove = duplicates.flatMap { $0.unifiedNotes ?? [] }
        for note in notesToMove {
            note.work = canonical
        }
    }

    /// Merges dates: earliest assignedAt, earliest dueAt, most recent lastTouchedAt.
    private func mergeDates(into canonical: WorkModel, from duplicates: [WorkModel]) {
        for duplicate in duplicates {
            if duplicate.assignedAt < canonical.assignedAt {
                canonical.assignedAt = duplicate.assignedAt
            }
            if let dupDueAt = duplicate.dueAt {
                if let canonicalDueAt = canonical.dueAt {
                    canonical.dueAt = min(canonicalDueAt, dupDueAt)
                } else {
                    canonical.dueAt = dupDueAt
                }
            }
            if let dupLastTouched = duplicate.lastTouchedAt {
                if let canonicalLastTouched = canonical.lastTouchedAt {
                    canonical.lastTouchedAt = max(canonicalLastTouched, dupLastTouched)
                } else {
                    canonical.lastTouchedAt = dupLastTouched
                }
            }
        }
    }

    /// If any duplicate is completed but canonical is not, transfer completion status.
    private func mergeCompletionStatus(into canonical: WorkModel, from duplicates: [WorkModel]) {
        for duplicate in duplicates {
            if duplicate.completedAt != nil && canonical.completedAt == nil {
                canonical.completedAt = duplicate.completedAt
                canonical.status = duplicate.status
                if let outcome = duplicate.completionOutcome {
                    canonical.completionOutcome = outcome
                }
            }
        }
    }
}
