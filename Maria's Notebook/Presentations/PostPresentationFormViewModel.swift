import Foundation
import SwiftData
import SwiftUI

/// ViewModel for managing post-presentation form state and logic.
/// Works with UnifiedPostPresentationSheet's nested types for compatibility.
@Observable
@MainActor
final class PostPresentationFormViewModel {
    // MARK: - Type Aliases (using sheet's nested types)

    typealias PresentationStatus = UnifiedPostPresentationSheet.PresentationStatus
    typealias StudentEntry = UnifiedPostPresentationSheet.StudentEntry

    // MARK: - State

    var status: PresentationStatus
    var entries: [UUID: StudentEntry] = [:]
    var groupObservation: String = ""
    var bulkAssignment: String = ""
    var defaultCheckInEnabled: Bool = false
    var defaultCheckInDate: Date
    var defaultDueEnabled: Bool = false
    var defaultDueDate: Date
    var expandedStudentIDs: Set<UUID> = []
    var studentsToUnlock: Set<UUID> = []

    // MARK: - Computed Properties
    
    var canDismiss: Bool {
        status == .justPresented || status == .previouslyPresented
    }

    // MARK: - Initialization
    
    init(students: [Student], initialStatus: PresentationStatus = .justPresented) {
        // Initialize status
        self.status = initialStatus
        
        // Default dates
        self.defaultCheckInDate = AppCalendar.startOfDay(Date().addingTimeInterval(24*60*60))
        self.defaultDueDate = AppCalendar.startOfDay(Date().addingTimeInterval(7*24*60*60))

        // Initialize entries
        self.entries = Dictionary(
            uniqueKeysWithValues: students.map { student in
                (student.id, StudentEntry(id: student.id, name: StudentFormatter.displayName(for: student)))
            }
        )
        
        // Auto-expand all students by default
        self.expandedStudentIDs = Set(students.map { $0.id })
    }

    // MARK: - Actions
    
    /// Applies the bulk assignment text to all students.
    func applyBulkAssignment() {
        let trimmed = bulkAssignment.trimmed()
        guard !trimmed.isEmpty else { return }

        for (id, entry) in entries {
            var updated = entry
            updated.assignment = trimmed

            if defaultCheckInEnabled && entry.checkInDate == nil {
                updated.checkInDate = defaultCheckInDate
            }
            if defaultDueEnabled && entry.dueDate == nil {
                updated.dueDate = defaultDueDate
            }

            entries[id] = updated
        }

        bulkAssignment = ""
    }

    /// Returns final entries as array with default dates applied to entries with assignments.
    func getFinalEntries() -> [StudentEntry] {
        var finalEntries = entries

        // Apply default dates to entries with assignments
        for (id, entry) in finalEntries {
            var updated = entry

            if !entry.assignment.isEmpty {
                if defaultCheckInEnabled && entry.checkInDate == nil {
                    updated.checkInDate = defaultCheckInDate
                }
                if defaultDueEnabled && entry.dueDate == nil {
                    updated.dueDate = defaultDueDate
                }
            }

            finalEntries[id] = updated
        }

        return Array(finalEntries.values)
    }

    /// Unlocks next lessons for selected students.
    func unlockNextLessonsIfNeeded(
        lessonID: UUID,
        modelContext: ModelContext,
        lessons: [Lesson],
        studentLessons: [StudentLesson]
    ) {
        guard !studentsToUnlock.isEmpty else { return }

        _ = UnlockNextLessonService.unlockNextLesson(
            after: lessonID,
            for: studentsToUnlock,
            modelContext: modelContext,
            lessons: lessons,
            studentLessons: studentLessons
        )
    }
}
