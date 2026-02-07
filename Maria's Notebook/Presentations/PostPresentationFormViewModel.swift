import Foundation
import SwiftData
import SwiftUI
import Combine

/// ViewModel for managing post-presentation form state and logic.
@MainActor
final class PostPresentationFormViewModel: ObservableObject {
    // MARK: - Nested Types
    
    enum PresentationStatus: String, CaseIterable, Identifiable {
        case justPresented
        case previouslyPresented
        case needsAnother

        var id: String { rawValue }

        var title: String {
            switch self {
            case .justPresented: return "Just Presented"
            case .previouslyPresented: return "Previously Presented"
            case .needsAnother: return "Needs Another"
            }
        }

        var systemImage: String {
            switch self {
            case .justPresented: return "checkmark.circle.fill"
            case .previouslyPresented: return "clock.badge.checkmark"
            case .needsAnother: return "arrow.clockwise.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .justPresented, .previouslyPresented: return .green
            case .needsAnother: return .orange
            }
        }
    }
    
    // MARK: - Published State
    
    @Published var status: PresentationStatus
    @Published var entries: [UUID: PresentationStudentEntry] = [:]
    @Published var groupObservation: String = ""
    @Published var bulkAssignment: String = ""
    @Published var defaultCheckInEnabled: Bool = false
    @Published var defaultCheckInDate: Date
    @Published var defaultDueEnabled: Bool = false
    @Published var defaultDueDate: Date
    @Published var expandedStudentIDs: Set<UUID> = []
    @Published var studentsToUnlock: Set<UUID> = []

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
                (student.id, PresentationStudentEntry(id: student.id, name: student.firstName))
            }
        )
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

    /// Returns final entries with default dates applied to entries with assignments.
    func getFinalEntries() -> [UUID: PresentationStudentEntry] {
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

        return finalEntries
    }

    /// Unlocks next lessons for selected students.
    func unlockNextLessonsIfNeeded(
        modelContext: ModelContext,
        lesson: Lesson,
        allLessons: [Lesson],
        allStudentLessons: [StudentLesson]
    ) {
        guard !studentsToUnlock.isEmpty else { return }

        let studentIDStrings = studentsToUnlock.map { $0.uuidString }

        UnlockNextLessonService.unlockNextLesson(
            afterLesson: lesson,
            forStudentIDs: studentIDStrings,
            allLessons: allLessons,
            allStudentLessons: allStudentLessons,
            modelContext: modelContext
        )
    }
}
