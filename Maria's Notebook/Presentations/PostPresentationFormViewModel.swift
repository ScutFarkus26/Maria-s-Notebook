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

    // MARK: - Next Lesson Action

    enum NextLessonAction: String, CaseIterable, Identifiable {
        case hold = "Hold"
        case inbox = "Inbox"
        case schedule = "Schedule"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .hold: return "pause.circle.fill"
            case .inbox: return "tray.fill"
            case .schedule: return "calendar.badge.plus"
            }
        }
    }

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

    // Next lesson state
    var nextLessonAction: NextLessonAction = .inbox
    var nextLessonScheduleDate: Date = AppCalendar.startOfDay(Date().addingTimeInterval(24 * 60 * 60))
    var nextLesson: Lesson?
    var existingNextAssignment: LessonAssignment?
    var isNextLessonSectionExpanded: Bool = false

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
        lessonAssignments: [LessonAssignment]
    ) {
        guard !studentsToUnlock.isEmpty else { return }

        _ = UnlockNextLessonService.unlockNextLesson(
            after: lessonID,
            for: studentsToUnlock,
            modelContext: modelContext,
            lessons: lessons,
            lessonAssignments: lessonAssignments
        )
    }

    // MARK: - Next Lesson

    /// Looks up the next lesson in the sequence and checks for existing assignments.
    func resolveNextLesson(
        lessonID: UUID,
        studentIDs: Set<UUID>,
        lessons: [Lesson],
        lessonAssignments: [LessonAssignment]
    ) {
        guard let currentLesson = lessons.first(where: { $0.id == lessonID }) else {
            nextLesson = nil
            return
        }

        nextLesson = PlanNextLessonService.findNextLesson(after: currentLesson, in: lessons)

        guard let nextLesson else { return }

        // Check for existing assignment (any state: inbox or scheduled)
        existingNextAssignment = lessonAssignments.first { la in
            la.lessonIDUUID == nextLesson.id &&
            Set(la.studentUUIDs) == studentIDs &&
            la.presentedAt == nil
        }

        // If already exists, reflect its current state in the picker
        if let existing = existingNextAssignment {
            if existing.scheduledFor != nil {
                nextLessonAction = .schedule
                nextLessonScheduleDate = existing.scheduledFor!
            } else {
                nextLessonAction = .inbox
            }
        }
    }

    /// Whether any work has been assigned (bulk or per-student).
    var hasWorkAssigned: Bool {
        if !bulkAssignment.trimmed().isEmpty { return true }
        return entries.values.contains { !$0.assignment.isEmpty }
    }

    /// Whether the hold option should be enabled (requires work to be assigned).
    var isHoldEnabled: Bool {
        hasWorkAssigned
    }

    /// Executes the chosen next lesson action.
    func executeNextLessonAction(
        studentIDs: Set<UUID>,
        allStudents: [Student],
        allLessons: [Lesson],
        lessonAssignments: [LessonAssignment],
        modelContext: ModelContext
    ) {
        guard let nextLesson else { return }

        switch nextLessonAction {
        case .hold:
            // Do nothing — blocking algorithm handles it naturally
            break

        case .inbox:
            if let existing = existingNextAssignment {
                // Update existing to draft/inbox state
                existing.state = .draft
                existing.scheduledFor = nil
            } else {
                // Create new draft
                PlanNextLessonService.planLesson(
                    nextLesson,
                    forStudents: studentIDs,
                    allStudents: allStudents,
                    allLessons: allLessons,
                    existingLessonAssignments: lessonAssignments,
                    context: modelContext
                )
            }

        case .schedule:
            if let existing = existingNextAssignment {
                // Update existing to scheduled
                existing.state = .scheduled
                existing.scheduledFor = nextLessonScheduleDate
            } else {
                // Create new scheduled assignment
                let la = PresentationFactory.makeScheduled(
                    lessonID: nextLesson.id,
                    studentIDs: Array(studentIDs),
                    scheduledFor: nextLessonScheduleDate
                )
                let relatedStudents = allStudents.filter { studentIDs.contains($0.id) }
                PresentationFactory.attachRelationships(
                    to: la,
                    lesson: allLessons.first(where: { $0.id == nextLesson.id }),
                    students: relatedStudents
                )
                modelContext.insert(la)
            }
        }
    }
}
