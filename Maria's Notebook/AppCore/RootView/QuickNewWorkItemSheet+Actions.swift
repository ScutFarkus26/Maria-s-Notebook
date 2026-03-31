// QuickNewWorkItemSheet+Actions.swift
// Save logic and check-in reason helpers for QuickNewWorkItemSheet.

import SwiftUI
import CoreData

extension QuickNewWorkItemSheet {

    // MARK: - Save

    func saveWorkItem(andOpen: Bool) {
        guard let lessonID = selectedLessonID,
              !selectedStudentIDs.isEmpty else { return }
        isSaving = true

        let repository = WorkRepository(context: viewContext)

        do {
            var createdWorkID: UUID?
            // Create work for each selected student
            for studentID in selectedStudentIDs {
                let work = try repository.createWork(
                    studentID: studentID,
                    lessonID: lessonID,
                    title: workTitle.isEmpty ? nil : workTitle,
                    kind: workKind,
                    scheduledDate: hasDueDate ? dueDate : nil,
                    sampleWorkID: selectedSampleWorkID
                )

                // Set check-in style for multi-student work
                if selectedStudentIDs.count > 1 {
                    work.checkInStyle = checkInStyle
                }

                // Create check-in if scheduled
                if hasCheckIn, let workID = work.id {
                    let normalized = AppCalendar.startOfDay(checkInDate)

                    // Create WorkCheckIn for scheduled check-ins
                    let checkIn = CDWorkCheckIn(context: viewContext)
                    checkIn.workID = workID.uuidString
                    checkIn.date = normalized
                    checkIn.status = WorkCheckInStatus.scheduled
                    checkIn.purpose = CheckInMigrationService.mapReasonToPurpose(checkInReason)
                }

                // Keep reference to first created work for "Create & Open"
                if createdWorkID == nil {
                    createdWorkID = work.id
                }
            }
            saveCoordinator.save(viewContext, reason: "Quick New Work Item")
            dismiss()

            // If user wants to open the detail view, call the callback after dismiss
            if andOpen, let workID = createdWorkID {
                onCreatedAndOpen?(workID)
            }
        } catch {
            isSaving = false
        }
    }

    // MARK: - Check-In Reason Helpers

    func legacyReasonIcon(_ reason: CheckInMigrationService.CheckInReason) -> String {
        switch reason {
        case .progressCheck: return "checkmark.circle"
        case .dueDate: return "calendar.badge.exclamationmark"
        case .assessment: return "doc.text.magnifyingglass"
        case .followUp: return "arrow.turn.up.right"
        case .studentRequest: return "person.bubble"
        case .other: return "ellipsis.circle"
        }
    }

    func legacyReasonLabel(_ reason: CheckInMigrationService.CheckInReason) -> String {
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
