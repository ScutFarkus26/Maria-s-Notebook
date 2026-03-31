// PresentationDetailViewModel.swift
// Core state, initialization, save/delete, and lifecycle for lesson assignment detail editing.
//
// Extensions:
// - PresentationDetailViewModel+NotesAutosave.swift    (scheduleNotesAutosave, flush)
// - PresentationDetailViewModel+MasteryTracking.swift  (loadProficiencyState, updateProficiencyState)
// - PresentationDetailViewModel+StudentActions.swift   (moveStudentsToInbox, handleNeedsAnotherChange,
//                                                       scheduleNextLessonToInbox)

import Foundation
import SwiftUI
import CoreData
import OSLog

@Observable
@MainActor
final class PresentationDetailViewModel {
    static let logger = Logger.students

    // MARK: - Dependencies
    var lessonAssignment: CDLessonAssignment
    var viewContext: NSManagedObjectContext
    var saveCoordinator: SaveCoordinator

    // MARK: - Editable State
    var editingLessonID: UUID
    var scheduledFor: Date?
    var givenAt: Date?
    var isPresented: Bool
    var notes: String {
        didSet {
            scheduleNotesAutosave()
        }
    }
    var needsAnotherPresentation: Bool
    var selectedStudentIDs: Set<UUID>

    // MARK: - Mastery State
    /// The mastery state for progress tracking. Only applies when lesson is presented.
    /// nil = not yet loaded, .presented = shown but not mastered, .proficient = student has mastered
    var proficiencyState: LessonPresentationState = .presented

    // MARK: - UI State
    var showLessonPicker: Bool = false
    var showAssignmentComposer: Bool = false
    var showingAddStudentSheet: Bool = false
    var showingStudentPickerPopover: Bool = false
    var showDeleteAlert: Bool = false
    var showingMoveStudentsSheet: Bool = false
    var showingFindStudentsSheet: Bool = false

    // MARK: - Workflow Panel State (for embedded presentation workflow)
    var showWorkflowPanel: Bool = false
    var presentationViewModel: PostPresentationFormViewModel?
    var savedScrollPosition: CGPoint = .zero
    var hasUnsavedWorkflowChanges: Bool = false

    // MARK: - Move Students UI State
    var studentsToMove: Set<UUID> = []
    var showMovedBanner: Bool = false
    var movedStudentNames: [String] = []

    // MARK: - Autosave State
    var notesDirty: Bool = false
    var originalNotes: String
    // Internal (not private) so +NotesAutosave extension can manage this task.
    var notesAutosaveTask: Task<Void, Never>?

    // MARK: - Initialization

    init(
        lessonAssignment: CDLessonAssignment,
        viewContext: NSManagedObjectContext,
        saveCoordinator: SaveCoordinator,
        autoFocusLessonPicker: Bool = false
    ) {
        self.lessonAssignment = lessonAssignment
        self.viewContext = viewContext
        self.saveCoordinator = saveCoordinator

        // Initialize local state from the model
        self.editingLessonID = UUID(uuidString: lessonAssignment.lessonID) ?? UUID()
        self.scheduledFor = lessonAssignment.scheduledFor
        self.givenAt = lessonAssignment.presentedAt
        self.isPresented = lessonAssignment.isPresented
        self.notes = lessonAssignment.notes
        self.originalNotes = lessonAssignment.notes
        self.needsAnotherPresentation = lessonAssignment.needsAnotherPresentation
        self.selectedStudentIDs = Set(lessonAssignment.studentIDs.compactMap { UUID(uuidString: $0) })

        self.showLessonPicker = autoFocusLessonPicker

        // Load mastery state from existing CDLessonPresentation records
        self.proficiencyState = Self.loadProficiencyState(
            lessonID: lessonAssignment.lessonID,
            studentIDs: lessonAssignment.studentIDs,
            viewContext: viewContext
        )
    }

    // MARK: - Error Handling Helpers

    /// Internal (not private) so +MasteryTracking extension can call it.
    func safeFetch<T>(_ descriptor: NSFetchRequest<T>, functionName: String = #function) -> [T] {
        do {
            return try viewContext.fetch(descriptor)
        } catch {
            Self.logger.warning("[\(functionName)] Failed to fetch \(String(describing: T.self)): \(error)")
            return []
        }
    }

    // MARK: - Computed Helpers

    /// Resolves the currently selected CDLesson object from the provided list
    func lessonObject(from lessons: [CDLesson]) -> CDLesson? {
        lessons.first(where: { $0.id == editingLessonID })
    }

    /// Determines the next lesson in the group based on the current selection
    func nextLessonInGroup(from lessons: [CDLesson]) -> CDLesson? {
        guard let current = lessonObject(from: lessons) else { return nil }
        let actions = PresentationDetailActions()
        return actions.nextLessonInGroup(from: current, lessons: lessons)
    }

    // MARK: - Actions

    /// Applies local state to the persistent model without saving (useful for immediate updates)
    func applyEditsToModel(studentsAll: [CDStudent], lessons: [CDLesson], calendar: Calendar) {
        let actions = PresentationDetailActions()
        actions.applyEditsToModel(
            lessonAssignment: lessonAssignment,
            editingLessonID: editingLessonID,
            scheduledFor: scheduledFor,
            givenAt: givenAt,
            isPresented: isPresented,
            notes: notes,
            needsAnotherPresentation: needsAnotherPresentation,
            selectedStudentIDs: selectedStudentIDs,
            studentsAll: studentsAll,
            lessons: lessons,
            calendar: calendar
        )
    }

    // Saves changes to the database, handles lifecycle events, and auto-creates next lessons
    func save(
        studentsAll: [CDStudent],
        lessons: [CDLesson],
        lessonAssignmentsAll: [CDLessonAssignment],
        calendar: Calendar,
        onDone: (() -> Void)? = nil
    ) {
        // Capture prior presented state
        let wasGiven = lessonAssignment.isPresented

        // 1. Apply local edits to the model
        applyEditsToModel(studentsAll: studentsAll, lessons: lessons, calendar: calendar)

        // 2. Engagement Lifecycle (Record Presentation)
        let nowGiven = handleEngagementLifecycle()

        // 3. Auto-create next lesson if needed
        let actions = PresentationDetailActions()
        let nextLesson = nextLessonInGroup(from: lessons)

        actions.autoCreateNextIfNeeded(
            wasGiven: wasGiven,
            nowGiven: nowGiven,
            nextLesson: nextLesson,
            selectedStudentIDs: selectedStudentIDs,
            studentsAll: studentsAll,
            lessons: lessons,
            lessonAssignmentsAll: lessonAssignmentsAll,
            context: viewContext
        )

        // 4. Persist
        if saveCoordinator.save(viewContext, reason: "Saving lesson assignment") {
            // Reset autosave state
            notesAutosaveTask?.cancel()
            originalNotes = notes
            notesDirty = false

            // Notify system
            PresentationDetailUtilities.notifyInboxRefresh()

            onDone?()
        }
    }

    // Handles recording presentation, mastery updates, and track enrollment. Returns nowGiven.
    private func handleEngagementLifecycle() -> Bool {
        let nowGiven = isPresented || (givenAt != nil)
        if nowGiven {
            do {
                _ = try LifecycleService.recordPresentation(
                    from: lessonAssignment,
                    presentedAt: AppCalendar.startOfDay(givenAt ?? Date()),
                    modelContext: viewContext
                )
            } catch {
                Self.logger.debug("LifecycleService error: \(error)")
            }

            updateProficiencyState(
                lessonID: lessonAssignment.lessonID,
                studentIDs: lessonAssignment.studentIDs,
                state: proficiencyState
            )

            if let lesson = lessonAssignment.lesson {
                GroupTrackService.autoEnrollInTrackIfNeeded(
                    lessonSubject: lesson.subject,
                    lessonGroup: lesson.group,
                    studentIDs: lessonAssignment.studentIDs,
                    context: viewContext,
                    saveCoordinator: saveCoordinator
                )
            }
        }

        if !nowGiven, lessonAssignment.scheduledFor != nil {
            if let lesson = lessonAssignment.lesson {
                GroupTrackService.autoEnrollInTrackIfNeeded(
                    lessonSubject: lesson.subject,
                    lessonGroup: lesson.group,
                    studentIDs: lessonAssignment.studentIDs,
                    context: viewContext,
                    saveCoordinator: saveCoordinator
                )
            }
        }

        return nowGiven
    }

    /// A lightweight save for autosaving notes or minor updates
    func saveImmediate(studentsAll: [CDStudent], lessons: [CDLesson], calendar: Calendar) {
        applyEditsToModel(studentsAll: studentsAll, lessons: lessons, calendar: calendar)
        saveCoordinator.save(viewContext, reason: "Auto-saving lesson assignment")
    }

    /// Deletes the lesson assignment
    func delete(onDone: (() -> Void)? = nil) {
        let id = lessonAssignment.id ?? UUID()
        let ctx = viewContext
        let coordinator = saveCoordinator

        // Execute callback immediately to dismiss UI
        onDone?()

        // Perform deletion asynchronously
        Task { @MainActor in
            var desc = { let r = NSFetchRequest<CDLessonAssignment>(entityName: "LessonAssignment"); r.predicate = NSPredicate(format: "id == %@", id as CVarArg); r.fetchLimit = 0; return r }()
            desc.fetchLimit = 1
            do {
                if let toDelete = try ctx.fetch(desc).first {
                    _ = toDelete.studentIDs
                    ctx.delete(toDelete)
                    coordinator.save(ctx, reason: "Deleting lesson assignment")
                }
            } catch {
                Self.logger.warning("Failed to fetch CDLessonAssignment for deletion: \(error)")
            }
            PresentationDetailUtilities.notifyInboxRefresh()
        }
    }

    // MARK: - Workflow Panel Management

    /// Enters workflow mode by initializing the presentation view model
    func enterWorkflowMode(students: [CDStudent]) {
        presentationViewModel = PostPresentationFormViewModel(students: students)
        showWorkflowPanel = true
    }

    /// Exits workflow mode and cleans up the presentation view model
    func exitWorkflowMode() {
        presentationViewModel = nil
        showWorkflowPanel = false
    }
}
