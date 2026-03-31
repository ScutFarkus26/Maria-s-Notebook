import Foundation
import CoreData

/// Service for consolidating duplicate CDWorkModel records.
/// Duplicates are identified by matching title, studentLessonID, and workType.
@MainActor
struct WorkConsolidationService {
    let context: NSManagedObjectContext

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

        let request = CDFetchRequest(CDWorkModel.self)
        let allWorks = context.safeFetch(request)

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

            guard let canonical = group.min(by: { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }) else {
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

        if !context.safeSave() {
            errors.append("Failed to save changes")
        }

        return ConsolidationResult(groupsConsolidated: groupsConsolidated, totalMerged: totalMerged, errors: errors)
    }

    // MARK: - Merge Helpers

    /// Merges participants from duplicates into the canonical work, preserving earliest completion dates.
    private func mergeParticipants(into canonical: CDWorkModel, from duplicates: [CDWorkModel]) {
        var allParticipantIDs = Set<String>()
        for work in [canonical] + duplicates {
            let parts = (work.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
            for participant in parts {
                allParticipantIDs.insert(participant.studentID)
            }
        }
        guard !allParticipantIDs.isEmpty else { return }

        let existingParts = (canonical.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
        let existingParticipantIDs = Set(existingParts.map(\.studentID))

        for participantID in allParticipantIDs {
            if !existingParticipantIDs.contains(participantID) {
                addNewParticipant(participantID, into: canonical, from: duplicates)
            } else {
                mergeExistingParticipantDates(participantID, canonical: canonical, duplicates: duplicates)
            }
        }
    }

    private func addNewParticipant(
        _ participantID: String, into canonical: CDWorkModel, from duplicates: [CDWorkModel]
    ) {
        guard let studentUUID = UUID(uuidString: participantID) else { return }

        // Collect earliest completion date from all duplicates
        var completedAt: Date?
        for duplicate in duplicates {
            let dupParts = (duplicate.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
            if let dupParticipant = dupParts.first(where: { $0.studentID == participantID }),
               let dupCompletedAt = dupParticipant.completedAt {
                if let existing = completedAt {
                    completedAt = min(existing, dupCompletedAt)
                } else {
                    completedAt = dupCompletedAt
                }
            }
        }

        let newParticipant = CDWorkParticipantEntity(context: context)
        newParticipant.studentID = studentUUID.uuidString
        newParticipant.completedAt = completedAt
        newParticipant.work = canonical
        canonical.addToParticipants(newParticipant)
    }

    private func mergeExistingParticipantDates(
        _ participantID: String, canonical: CDWorkModel, duplicates: [CDWorkModel]
    ) {
        let canonicalParts = (canonical.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
        guard let existingParticipant = canonicalParts.first(
            where: { $0.studentID == participantID }
        ) else { return }

        for duplicate in duplicates {
            let dupParts = (duplicate.participants?.allObjects as? [CDWorkParticipantEntity]) ?? []
            if let dupParticipant = dupParts.first(where: { $0.studentID == participantID }),
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
    private func mergeNotes(into canonical: CDWorkModel, from duplicates: [CDWorkModel]) {
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
    private func mergeCheckInsAndUnifiedNotes(into canonical: CDWorkModel, from duplicates: [CDWorkModel]) {
        for duplicate in duplicates {
            let dupCheckIns = (duplicate.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []
            for checkIn in dupCheckIns {
                checkIn.work = canonical
                canonical.addToCheckIns(checkIn)
            }
        }

        let notesToMove = duplicates.flatMap { ($0.unifiedNotes?.allObjects as? [CDNote]) ?? [] }
        for note in notesToMove {
            note.work = canonical
        }
    }

    /// Merges dates: earliest assignedAt, earliest dueAt, most recent lastTouchedAt.
    private func mergeDates(into canonical: CDWorkModel, from duplicates: [CDWorkModel]) {
        for duplicate in duplicates {
            if let dupAssignedAt = duplicate.assignedAt, let canonicalAssignedAt = canonical.assignedAt {
                if dupAssignedAt < canonicalAssignedAt {
                    canonical.assignedAt = dupAssignedAt
                }
            } else if let dupAssignedAt = duplicate.assignedAt, canonical.assignedAt == nil {
                canonical.assignedAt = dupAssignedAt
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
    private func mergeCompletionStatus(into canonical: CDWorkModel, from duplicates: [CDWorkModel]) {
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
