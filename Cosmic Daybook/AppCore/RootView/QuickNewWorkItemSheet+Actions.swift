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
    /// participants, through `WorkAssignmentService`, the one way work is
    /// given (Claude's `assign_work` uses it too). The check-in lands on a
    /// school day: picked for a weekend or a day off, it moves forward to the
    /// next one. The sheet used to make it on the day picked, closed or not
    /// (domain logic review 2026-11-20, A3). Nothing is saved here.
    private func makeWorkRows(lessonID: UUID) throws -> [CDWorkModel] {
        let title = workTitle.trimmed()
        let assigned = try WorkAssignmentService(context: viewContext).create(.init(
            lessonID: lessonID,
            studentIDs: Array(selectedStudentIDs),
            title: title.isEmpty ? nil : title,
            kind: workKind,
            dueDate: hasDueDate ? dueDate : nil,
            sampleWorkID: selectedSampleWorkID,
            checkInStyle: checkInStyle,
            checkIn: hasCheckIn ? WorkAssignmentService.CheckIn(day: checkInDate, purpose: checkInReason.purpose) : nil
        ))
        if let landed = assigned.checkInDay, assigned.checkInAskedFor != nil {
            ToastService.shared.showInfo(
                "That isn't a school day, so the check-in is on \(DateFormatters.weekdayAndDate.string(from: landed))."
            )
        }
        return assigned.works
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
