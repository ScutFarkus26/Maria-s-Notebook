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

        // Fetch all WorkModel records
        let descriptor = FetchDescriptor<WorkModel>()
        let allWorks = context.safeFetch(descriptor)

        guard !allWorks.isEmpty else {
            return ConsolidationResult(groupsConsolidated: 0, totalMerged: 0, errors: [])
        }
        
        // Group works by duplicate criteria: title, studentLessonID, and kind
        let groups = allWorks.grouped { work -> String in
            let title = work.title.trimmed()
            let studentLessonID = work.studentLessonID?.uuidString ?? "nil"
            // Use kind for grouping
            let workKind = (work.kind ?? .research).rawValue
            return "\(title)|\(studentLessonID)|\(workKind)"
        }
        
        // Process each group
        for (_, group) in groups {
            guard group.count > 1 else { continue }
            
            groupsConsolidated += 1
            totalMerged += (group.count - 1)
            
            // Choose canonical: earliest createdAt
            guard let canonical = group.min(by: { $0.createdAt < $1.createdAt }) else {
                errors.append("Failed to find canonical work in group")
                continue
            }
            
            let duplicates = group.filter { $0.id != canonical.id }
            
            // Merge participants: union of all participant student IDs
            var allParticipantIDs = Set<String>()
            for work in group {
                if let participants = work.participants {
                    for participant in participants {
                        allParticipantIDs.insert(participant.studentID)
                    }
                }
            }
            
            // Update canonical with merged participants
            if !allParticipantIDs.isEmpty {
                // Get existing participants for canonical
                let existingParticipantIDs = Set((canonical.participants ?? []).map { $0.studentID })
                
                // Add missing participants and merge completion dates
                for participantID in allParticipantIDs {
                    if !existingParticipantIDs.contains(participantID),
                       let studentUUID = UUID(uuidString: participantID) {
                        // Collect completion dates from all duplicates for this participant
                        var completedAt: Date?
                        for duplicate in duplicates {
                            if let dupParticipants = duplicate.participants,
                               let dupParticipant = dupParticipants.first(where: { $0.studentID == participantID }),
                               let dupCompletedAt = dupParticipant.completedAt {
                                // Use the earliest completion date if multiple exist
                                if let existing = completedAt {
                                    completedAt = min(existing, dupCompletedAt)
                                } else {
                                    completedAt = dupCompletedAt
                                }
                            }
                        }
                        
                        // Create new participant
                        let newParticipant = WorkParticipantEntity(
                            studentID: studentUUID,
                            completedAt: completedAt,
                            work: canonical
                        )
                        if canonical.participants == nil {
                            canonical.participants = []
                        }
                        canonical.participants?.append(newParticipant)
                    } else if existingParticipantIDs.contains(participantID) {
                        // Participant already exists in canonical - merge completion dates
                        let canonicalParts = canonical.participants ?? []
                        if let existingParticipant = canonicalParts.first(
                            where: { $0.studentID == participantID }
                        ) {
                            // Check duplicates for earlier completion dates
                            for duplicate in duplicates {
                                if let dupParticipants = duplicate.participants,
                                   let dupParticipant = dupParticipants.first(where: { $0.studentID == participantID }),
                                   let dupCompletedAt = dupParticipant.completedAt {
                                    // Update to earliest completion date
                                    if let existingCompletedAt = existingParticipant.completedAt {
                                        if dupCompletedAt < existingCompletedAt {
                                            existingParticipant.completedAt = dupCompletedAt
                                        }
                                    } else {
                                        // Canonical doesn't have completion, but duplicate does
                                        existingParticipant.completedAt = dupCompletedAt
                                    }
                                }
                            }
                        }
                    }
                }
            }
            
            // Merge notes: prefer non-empty notes if canonical is empty
            let canonicalNoteText = canonical.latestUnifiedNoteText.trimmed()
            if canonicalNoteText.isEmpty {
                for duplicate in duplicates {
                    let dupNotes = duplicate.latestUnifiedNoteText.trimmed()
                    if !dupNotes.isEmpty {
                        canonical.setLegacyNoteText(dupNotes, in: context)
                        break
                    }
                }
            } else {
                // If canonical has notes, append non-empty notes from duplicates
                var combinedNotes = canonicalNoteText
                for duplicate in duplicates {
                    let dupNotes = duplicate.latestUnifiedNoteText.trimmed()
                    if !dupNotes.isEmpty && !combinedNotes.contains(dupNotes) {
                        if !combinedNotes.isEmpty {
                            combinedNotes += "\n\n"
                        }
                        combinedNotes += dupNotes
                    }
                }
                if combinedNotes != canonicalNoteText {
                    canonical.setLegacyNoteText(combinedNotes, in: context)
                }
            }
            
            // Merge check-ins: add all check-ins from duplicates
            for duplicate in duplicates {
                if let dupCheckIns = duplicate.checkIns {
                    if canonical.checkIns == nil {
                        canonical.checkIns = []
                    }
                    for checkIn in dupCheckIns {
                        // Update checkIn's work reference to canonical
                        checkIn.work = canonical
                        canonical.checkIns?.append(checkIn)
                    }
                }
            }
            
            // Re-parent unified notes
            let notesToMove = duplicates.flatMap { $0.unifiedNotes ?? [] }
            for note in notesToMove {
                note.work = canonical
            }
            
            // Merge dates: keep earliest assignedAt, earliest dueAt, most recent lastTouchedAt
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
            
            // Merge completion status: if any is completed, mark canonical as completed
            for duplicate in duplicates {
                if duplicate.completedAt != nil && canonical.completedAt == nil {
                    canonical.completedAt = duplicate.completedAt
                    canonical.status = duplicate.status
                    if let outcome = duplicate.completionOutcome {
                        canonical.completionOutcome = outcome
                    }
                }
            }
            
            // Delete duplicates
            for duplicate in duplicates {
                context.delete(duplicate)
            }
        }
        
        // Save changes
        do {
            try context.save()
        } catch {
            errors.append("Failed to save changes: \(error.localizedDescription)")
        }
        
        return ConsolidationResult(groupsConsolidated: groupsConsolidated, totalMerged: totalMerged, errors: errors)
    }
}
