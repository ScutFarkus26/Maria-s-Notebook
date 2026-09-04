import Foundation
import SwiftUI
import CoreData

/// The small amount of per-student information collected after a presentation.
/// Detailed follow-up work lives in `workDrafts`, so there is only one editable
/// source for assignments.
struct PostPresentationStudentEntry: Identifiable {
    let id: UUID
    let name: String
    var observation: String = ""
}

/// ViewModel for managing post-presentation form state and logic.
@Observable
final class PostPresentationFormViewModel {
    // MARK: - Next CDLesson Action

    enum NextLessonAction: String, CaseIterable, Identifiable {
        case noChange = "Keep Watching"
        case inbox = "Add to Inbox"
        case schedule = "Schedule"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .noChange: return "minus.circle"
            case .inbox: return "tray.fill"
            case .schedule: return "calendar.badge.plus"
            }
        }
    }

    // MARK: - State

    var entries: [UUID: PostPresentationStudentEntry] = [:]
    var groupObservation: String = ""
    var bulkAssignment: String = ""
    var workDrafts: [UUID: [WorkItemDraft]] = [:]
    var defaultCheckInEnabled: Bool = false
    var defaultCheckInDate: Date
    var defaultDueEnabled: Bool = false
    var defaultDueDate: Date
    var expandedStudentIDs: Set<UUID> = []
    var studentsToUnlock: Set<UUID> = []

    // Progression rules (resolved for the lesson being presented)
    var resolvedRules: LessonProgressionRules.ResolvedRules?
    /// Per-student proficiency confirmation (studentID -> confirmed)
    var confirmedStudentIDs: Set<UUID> = []

    // Next lesson state
    var nextLessonAction: NextLessonAction = .noChange
    var nextLessonScheduleDate: Date = AppCalendar.startOfDay(Date().addingTimeInterval(24 * 60 * 60))
    var nextLesson: CDLesson?
    var existingNextAssignment: CDLessonAssignment?
    var isNextLessonSectionExpanded: Bool = false
    private var nextLessonResolutionKey: NextLessonResolutionKey?

    // MARK: - Computed Properties

    /// Whether the form has unsaved content the user would lose by dismissing.
    var hasUnsavedContent: Bool {
        if !groupObservation.trimmed().isEmpty { return true }
        if !bulkAssignment.trimmed().isEmpty { return true }
        if entries.values.contains(where: { !$0.observation.trimmed().isEmpty }) {
            return true
        }
        if workDrafts.values.joined().contains(where: Self.isMeaningfulWorkDraft) { return true }
        if !confirmedStudentIDs.isEmpty { return true }
        if !studentsToUnlock.isEmpty { return true }
        if nextLessonAction != .noChange { return true }
        return false
    }

    // MARK: - Initialization
    
    init(students: [CDStudent]) {
        // Default dates
        self.defaultCheckInDate = AppCalendar.startOfDay(Date().addingTimeInterval(24*60*60))
        self.defaultDueDate = AppCalendar.startOfDay(Date().addingTimeInterval(7*24*60*60))

        // Initialize entries
        self.entries = Dictionary(
            uniqueKeysWithValues: students.compactMap { student -> (UUID, PostPresentationStudentEntry)? in
                guard let id = student.id else { return nil }
                return (id, PostPresentationStudentEntry(id: id, name: StudentFormatter.displayName(for: student)))
            }
        )

        // Auto-expand all students by default
        self.expandedStudentIDs = Set(students.compactMap(\.id))
    }

    // MARK: - Actions

    /// Unlocks next lessons for selected students.
    func unlockNextLessonsIfNeeded(
        lessonID: UUID,
        viewContext: NSManagedObjectContext,
        lessons: [CDLesson],
        lessonAssignments: [CDLessonAssignment]
    ) {
        guard !studentsToUnlock.isEmpty else { return }

        _ = UnlockNextLessonService.unlockNextLesson(
            after: lessonID,
            for: studentsToUnlock,
            context: viewContext,
            lessons: lessons,
            cdAssignments: lessonAssignments,
            saveImmediately: false
        )
    }

    // MARK: - Next CDLesson

    /// Resolves progression rules for the lesson being presented.
    func resolveProgressionRules(lessonID: UUID, lessons: [CDLesson], context: NSManagedObjectContext) {
        guard let lesson = lessons.first(where: { $0.id == lessonID }) else { return }
        resolvedRules = LessonProgressionRules.resolve(for: lesson, context: context)
    }

    /// Whether the lesson requires follow-up practice per progression rules.
    var requiresPractice: Bool {
        resolvedRules?.requiresPractice ?? false
    }

    /// Whether the lesson requires teacher confirmation per progression rules.
    var requiresConfirmation: Bool {
        resolvedRules?.requiresTeacherConfirmation ?? false
    }

    /// Toggle proficiency confirmation for a student.
    func toggleConfirmation(for studentID: UUID) {
        if confirmedStudentIDs.contains(studentID) {
            confirmedStudentIDs.remove(studentID)
        } else {
            confirmedStudentIDs.insert(studentID)
        }
    }

    /// Looks up the next lesson in the sequence and checks for existing assignments.
    func resolveNextLesson(
        lessonID: UUID,
        studentIDs: Set<UUID>,
        lessons: [CDLesson],
        lessonAssignments: [CDLessonAssignment],
        context: NSManagedObjectContext
    ) {
        // Resolve can run again when a Mac panel moves into its own window. Preserve
        // an explicit choice for the same lesson and roster, but reset when either
        // changes so a stale decision can never leak into another presentation.
        let resolutionKey = NextLessonResolutionKey(lessonID: lessonID, studentIDs: studentIDs)
        if nextLessonResolutionKey != resolutionKey {
            nextLessonAction = .noChange
            nextLessonResolutionKey = resolutionKey
        }
        existingNextAssignment = nil

        guard let currentLesson = lessons.first(where: { $0.id != nil && $0.id == lessonID }) else {
            nextLesson = nil
            return
        }

        nextLesson = PlanNextLessonService.findNextLesson(after: currentLesson, in: lessons)

        guard let nextLesson else { return }

        // Pre-fill the schedule date with the Year Plan's planned date (if any) so the
        // picker shows the planned date when the teacher switches to Schedule. A Year
        // Plan date is only a suggestion; it never selects an action.
        if let nextID = nextLesson.id,
           let planned = YearPlanPromotionService.plannedDate(
               lessonID: nextID.uuidString,
               studentIDs: studentIDs,
               context: context
           ) {
            nextLessonScheduleDate = planned
        }

        // Check for existing assignment (any state: inbox or scheduled)
        existingNextAssignment = lessonAssignments.first { la in
            nextLesson.id != nil && la.lessonIDUUID == nextLesson.id &&
            Set(la.studentUUIDs) == studentIDs &&
            !la.isPresented
        }

        // Keep No Change selected even when an assignment already exists. Its current
        // state is shown in the UI, and changing it still requires an explicit choice.
        if let existing = existingNextAssignment {
            if existing.scheduledFor != nil {
                nextLessonScheduleDate = existing.scheduledFor!
            }
        }
    }

    /// Executes the chosen next lesson action.
    func executeNextLessonAction(
        studentIDs: Set<UUID>,
        allStudents: [CDStudent],
        allLessons: [CDLesson],
        lessonAssignments: [CDLessonAssignment],
        viewContext: NSManagedObjectContext
    ) {
        guard nextLessonAction != .noChange else { return }
        guard let nextLesson else { return }

        // `existingNextAssignment` is a load-time snapshot. The unlock step in the
        // Done handler may have just created a draft for these students, so re-resolve
        // against the context (which sees pending inserts) before deciding whether to
        // update or create — otherwise Schedule/Inbox creates a second assignment.
        let resolvedExisting = existingNextAssignment
            ?? Self.fetchExistingAssignment(for: nextLesson, studentIDs: studentIDs, in: viewContext)

        switch nextLessonAction {
        case .noChange:
            return

        case .inbox:
            if let existing = resolvedExisting {
                existing.unschedule()
            } else {
                // Create new draft. Opt out of Year Plan auto-promote: the user explicitly
                // chose Inbox, so we must not schedule the assignment per the Year Plan.
                PlanNextLessonService.planLesson(
                    nextLesson,
                    forStudents: studentIDs,
                    allStudents: allStudents,
                    allLessons: allLessons,
                    existingLessonAssignments: lessonAssignments,
                    context: viewContext,
                    autoPromoteFromYearPlan: false
                )
            }

        case .schedule:
            if let existing = resolvedExisting {
                existing.schedule(for: nextLessonScheduleDate)
            } else {
                createScheduledAssignment(
                    for: nextLesson,
                    studentIDs: studentIDs,
                    allStudents: allStudents,
                    allLessons: allLessons,
                    viewContext: viewContext
                )
            }
        }
    }

    /// Creates a new scheduled assignment for the next lesson.
    private func createScheduledAssignment(
        for nextLesson: CDLesson,
        studentIDs: Set<UUID>,
        allStudents: [CDStudent],
        allLessons: [CDLesson],
        viewContext: NSManagedObjectContext
    ) {
        guard let nextLessonID = nextLesson.id else { return }
        let relatedStudents = allStudents.filter {
            guard let id = $0.id else { return false }
            return studentIDs.contains(id)
        }
        let nextLessonObj = allLessons.first(where: { $0.id != nil && $0.id == nextLessonID })
        if let nextLessonObj {
            _ = PresentationFactory.makeScheduled(
                lesson: nextLessonObj,
                students: relatedStudents,
                scheduledFor: nextLessonScheduleDate,
                context: viewContext
            )
        } else {
            _ = PresentationFactory.makeScheduled(
                lessonID: nextLessonID,
                studentIDs: Array(studentIDs),
                scheduledFor: nextLessonScheduleDate,
                context: viewContext
            )
        }
    }

    /// Finds a not-yet-presented assignment for the lesson covering these students,
    /// preferring an exact student-set match over a group assignment that contains
    /// them. Fetches through the context so pending (unsaved) inserts are visible.
    private static func fetchExistingAssignment(
        for lesson: CDLesson,
        studentIDs: Set<UUID>,
        in context: NSManagedObjectContext
    ) -> CDLessonAssignment? {
        guard let lessonID = lesson.id else { return nil }
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
        let unpresented = context.safeFetch(request).filter { !$0.isPresented }
        return unpresented.first { Set($0.studentUUIDs) == studentIDs }
            ?? unpresented.first { studentIDs.isSubset(of: Set($0.studentUUIDs)) }
    }

    nonisolated private static func isMeaningfulWorkDraft(_ draft: WorkItemDraft) -> Bool {
        !draft.title.trimmed().isEmpty
            || !draft.notes.trimmed().isEmpty
            || !draft.completionNote.trimmed().isEmpty
            || draft.checkInDate != nil
            || draft.dueDate != nil
            || draft.completionOutcome != nil
    }
}

private struct NextLessonResolutionKey: Equatable {
    let lessonID: UUID
    let studentIDs: Set<UUID>
}
