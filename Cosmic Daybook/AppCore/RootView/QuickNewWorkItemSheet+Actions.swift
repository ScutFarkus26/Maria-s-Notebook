// QuickNewWorkItemSheet+Actions.swift
// Save logic and check-in reason helpers for QuickNewWorkItemSheet.

import SwiftUI
import CoreData
import OSLog

extension QuickNewWorkItemSheet {

    // MARK: - Save

    /// Makes every child's row, then saves once. If any row or the save fails,
    /// every row made here is taken back out: nothing is left half-made for a
    /// group, and trying again can't make a second copy.
    func saveWorkItem(andOpen: Bool) {
        guard !isSaving else { return }
        guard let lessonID = selectedLessonID,
              !selectedStudentIDs.isEmpty else { return }
        isSaving = true

        let insertedBefore = viewContext.insertedObjects

        do {
            let createdWorks = try makeWorkRows(lessonID: lessonID)
            guard saveCoordinator.save(viewContext, reason: "Quick New Work Item", alertOnFailure: false) else {
                throw QuickNewWorkError.saveFailed
            }
            dismiss()

            // If user wants to open the detail view, call the callback after dismiss
            if andOpen, let workID = createdWorks.first?.id {
                onCreatedAndOpen?(workID)
            }
        } catch {
            Logger.work.warning("New Work wasn't created: \(error)")
            for object in viewContext.insertedObjects.subtracting(insertedBefore) {
                viewContext.delete(object)
            }
            saveErrorMessage = QuickNewWorkError.message(for: error)
            isSaving = false
        }
    }

    /// One work row per selected child, with its check-in and the group's
    /// participants. Nothing is saved here.
    private func makeWorkRows(lessonID: UUID) throws -> [CDWorkModel] {
        let repository = WorkRepository(context: viewContext)
        let title = workTitle.trimmed()
        var createdWorks: [CDWorkModel] = []

        for studentID in selectedStudentIDs {
            let work = try repository.createWork(
                studentID: studentID,
                lessonID: lessonID,
                title: title.isEmpty ? nil : title,
                kind: workKind,
                scheduledDate: hasDueDate ? dueDate : nil,
                sampleWorkID: selectedSampleWorkID,
                saveImmediately: false
            )

            // Set check-in style for multi-student work
            if selectedStudentIDs.count > 1 {
                work.checkInStyle = checkInStyle
            }

            // Create check-in if scheduled
            if hasCheckIn {
                CDWorkCheckIn.make(
                    for: work, on: AppCalendar.startOfDay(checkInDate),
                    purpose: checkInReason.purpose, in: viewContext
                )
            }

            createdWorks.append(work)
        }

        // Link multi-student work as participants on each other's work items
        if createdWorks.count > 1 {
            for work in createdWorks {
                for otherWork in createdWorks where otherWork !== work {
                    let participant = CDWorkParticipantEntity(context: viewContext)
                    participant.id = UUID()
                    participant.studentID = otherWork.studentID
                    participant.work = work
                }
            }
        }
        return createdWorks
    }

    // MARK: - Check-In Reason Helpers

    func legacyReasonIcon(_ reason: CheckInReason) -> String {
        switch reason {
        case .progressCheck: return "checkmark.circle"
        case .dueDate: return "calendar.badge.exclamationmark"
        case .assessment: return "doc.text.magnifyingglass"
        case .followUp: return "arrow.turn.up.right"
        case .studentRequest: return "person.bubble"
        case .other: return "ellipsis.circle"
        }
    }

    func legacyReasonLabel(_ reason: CheckInReason) -> String {
        switch reason {
        case .progressCheck: return "Progress Check"
        case .dueDate: return "Due Date"
        case .assessment: return "Assessment"
        case .followUp: return "Follow Up"
        case .studentRequest: return "Student Request"
        case .other: return "Other"
        }
    }
}

// MARK: - Save Failure

enum QuickNewWorkError: Error {
    case saveFailed

    /// The plain line New Work shows when nothing was made.
    static func message(for error: Error) -> String {
        if let refusal = error as? WorkRepository.AssignmentError, let reason = refusal.errorDescription {
            return reason + " Nothing was saved. Take them off the list and try again."
        }
        return "Couldn't create this work. Nothing was saved. Try again."
    }
}

// MARK: - Title Auto-Fill

/// New Work fills its title from the lesson, or from the template when one is
/// picked. A title the sheet filled in follows the next lesson or template;
/// one the guide typed stays.
nonisolated enum WorkTitleAutoFill {
    /// The title to show after picking `suggested`, or nil to leave hers alone.
    static func title(current: String, autoFilled: String?, suggested: String) -> String? {
        let typedOwn = !current.trimmed().isEmpty && current != autoFilled
        return typedOwn ? nil : suggested
    }
}
