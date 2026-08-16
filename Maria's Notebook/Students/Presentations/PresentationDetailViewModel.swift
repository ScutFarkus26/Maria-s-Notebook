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

    // MARK: - Group Recap
    /// Snapshot of every lesson, work item, and note in the same curriculum sequence as
    /// the current lesson, broken down per student. nil when there is no sequence to show
    /// (lesson has no sequence, or no lessons match). Recomputed on appear and whenever
    /// the editing lesson or roster changes.
    var groupRecap: SequenceRecap?

    /// Set to drive the WorkDetail sheet that opens when a work block in the sequence
    /// recap is tapped, or when a new work is created from the recap. The host view
    /// presents `.sheet(item: $vm.recapWorkSheetID)`; clearing it dismisses the sheet.
    var recapWorkSheetID: UUID?

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

    // MARK: - Group Recap

    /// Recomputes the sequence-recap snapshot for the current lesson + roster.
    /// Safe to call repeatedly; runs synchronously on the main actor and is fast for typical sequence sizes.
    func recomputeSequenceRecap(currentLesson: CDLesson?, students: [CDStudent]) {
        groupRecap = SequenceRecapResolver.resolve(
            currentLesson: currentLesson,
            students: students,
            context: viewContext
        )
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

    // Saves changes to the database and handles presentation lifecycle events.
    // Planning the next lesson only happens after an explicit choice in the
    // post-presentation workflow.
    func save(
        studentsAll: [CDStudent],
        lessons: [CDLesson],
        lessonAssignmentsAll _: [CDLessonAssignment],
        calendar: Calendar,
        onDone: (() -> Void)? = nil
    ) {
        // 1. Apply local edits to the model
        applyEditsToModel(studentsAll: studentsAll, lessons: lessons, calendar: calendar)

        // 2. Engagement Lifecycle (Record Presentation)
        handleEngagementLifecycle()

        // 3. Persist
        if saveCoordinator.save(viewContext, reason: "Saving lesson assignment") {
            // Reset autosave state
            notesAutosaveTask?.cancel()
            originalNotes = notes
            notesDirty = false

            // Auto-populate year plan entries when scheduling
            if lessonAssignment.state == .scheduled {
                Task {
                    await SequenceAutoPopulateService.autoPopulateSequence(
                        for: lessonAssignment,
                        scheduledDate: lessonAssignment.scheduledFor ?? Date(),
                        context: viewContext
                    )
                }
            }

            // Notify system
            PresentationDetailUtilities.notifyInboxRefresh()

            onDone?()
        }
    }

    // Handles recording presentation, mastery updates, and track enrollment.
    private func handleEngagementLifecycle() {
        let nowGiven = isPresented || (givenAt != nil)
        if nowGiven {
            if let givenAt {
                do {
                    _ = try LifecycleService.recordPresentation(
                        from: lessonAssignment,
                        presentedAt: AppCalendar.startOfDay(givenAt),
                        modelContext: viewContext
                    )
                } catch {
                    Self.logger.debug("LifecycleService error: \(error)")
                }
            } else {
                // "Previously Presented" is intentionally historical and
                // undated; never substitute today's date for missing knowledge.
                lessonAssignment.markPreviouslyPresented()
            }

            updateProficiencyState(
                lessonID: lessonAssignment.lessonID,
                studentIDs: lessonAssignment.studentIDs,
                state: proficiencyState
            )

            if let lesson = lessonAssignment.lesson {
                SequenceTrackService.autoEnrollInTrackIfNeeded(
                    lessonArea: lesson.area,
                    lessonSequence: lesson.sequence,
                    studentIDs: lessonAssignment.studentIDs,
                    context: viewContext,
                    saveCoordinator: saveCoordinator
                )
            }
        }

        if !nowGiven, lessonAssignment.scheduledFor != nil {
            if let lesson = lessonAssignment.lesson {
                SequenceTrackService.autoEnrollInTrackIfNeeded(
                    lessonArea: lesson.area,
                    lessonSequence: lesson.sequence,
                    studentIDs: lessonAssignment.studentIDs,
                    context: viewContext,
                    saveCoordinator: saveCoordinator
                )
            }
        }

    }

    /// Deletes the lesson assignment
    func delete(onDone: (() -> Void)? = nil) {
        // Cancel any pending notes autosave and clear the dirty flag BEFORE deleting,
        // so the dismissal-triggered onDisappear flush (flushNotesAutosaveIfNeeded)
        // is a no-op and never mutates/saves the object being deleted.
        notesAutosaveTask?.cancel()
        notesAutosaveTask = nil
        notesDirty = false

        let id = lessonAssignment.id ?? UUID()
        let ctx = viewContext
        let coordinator = saveCoordinator

        // Execute callback immediately to dismiss UI
        onDone?()

        // Perform deletion asynchronously
        Task { @MainActor in
            let desc: NSFetchRequest<CDLessonAssignment> = NSFetchRequest(entityName: "LessonAssignment")
            desc.predicate = NSPredicate(format: "id == %@", id as CVarArg)
            desc.fetchLimit = 1
            do {
                if let toDelete = try ctx.fetch(desc).first {
                    _ = toDelete.studentIDs
                    for row in PresentationFollowUpService.rows(for: id, in: ctx)
                        where row.hasOpenFollowUp {
                        PresentationFollowUpService.resolve(
                            .noFurtherFollowUp,
                            row: row
                        )
                    }
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
