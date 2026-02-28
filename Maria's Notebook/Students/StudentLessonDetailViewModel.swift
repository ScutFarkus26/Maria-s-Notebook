import Foundation
import SwiftData
import SwiftUI
import OSLog

@Observable
@MainActor
final class StudentLessonDetailViewModel {
    private static let logger = Logger.students
    // MARK: - Dependencies
    var studentLesson: StudentLesson
    var modelContext: ModelContext
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
    /// nil = not yet loaded, .presented = shown but not mastered, .mastered = student has mastered
    var masteryState: LessonPresentationState = .presented
    
    // MARK: - UI State
    var showLessonPicker: Bool = false
    var showAssignmentComposer: Bool = false
    var showingAddStudentSheet: Bool = false
    var showingStudentPickerPopover: Bool = false
    var showDeleteAlert: Bool = false
    var showingMoveStudentsSheet: Bool = false
    
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
    private var notesAutosaveTask: Task<Void, Never>? = nil

    // MARK: - Initialization
    init(studentLesson: StudentLesson, modelContext: ModelContext, saveCoordinator: SaveCoordinator, autoFocusLessonPicker: Bool = false) {
        self.studentLesson = studentLesson
        self.modelContext = modelContext
        self.saveCoordinator = saveCoordinator

        // Initialize local state from the model
        // CloudKit compatibility: Convert String lessonID to UUID
        self.editingLessonID = UUID(uuidString: studentLesson.lessonID) ?? UUID()
        self.scheduledFor = studentLesson.scheduledFor
        self.givenAt = studentLesson.givenAt
        self.isPresented = studentLesson.isPresented
        self.notes = studentLesson.notes
        self.originalNotes = studentLesson.notes
        self.needsAnotherPresentation = studentLesson.needsAnotherPresentation
        // Convert string IDs to UUIDs for CloudKit compatibility
        self.selectedStudentIDs = Set(studentLesson.studentIDs.compactMap { UUID(uuidString: $0) })

        self.showLessonPicker = autoFocusLessonPicker

        // Load mastery state from existing LessonPresentation records
        self.masteryState = Self.loadMasteryState(
            lessonID: studentLesson.lessonID,
            studentIDs: studentLesson.studentIDs,
            modelContext: modelContext
        )
    }

    // MARK: - Error Handling Helpers

    private func safeFetch<T>(_ descriptor: FetchDescriptor<T>, functionName: String = #function) -> [T] {
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Self.logger.warning("[\(functionName)] Failed to fetch \(String(describing: T.self)): \(error)")
            return []
        }
    }

    /// Loads the "highest" mastery state from all students' LessonPresentation records.
    /// If any student has mastered, returns .mastered. Otherwise returns .presented or the highest state found.
    private static func loadMasteryState(
        lessonID: String,
        studentIDs: [String],
        modelContext: ModelContext
    ) -> LessonPresentationState {
        guard !studentIDs.isEmpty, !lessonID.isEmpty else { return .presented }

        let allLessonPresentations: [LessonPresentation]
        do {
            allLessonPresentations = try modelContext.fetch(FetchDescriptor<LessonPresentation>())
        } catch {
            Self.logger.warning("Failed to fetch LessonPresentation: \(error)")
            return .presented
        }
        let matching = allLessonPresentations.filter { lp in
            lp.lessonID == lessonID && studentIDs.contains(lp.studentID)
        }

        // Return the "highest" state found (mastered > readyForAssessment > practicing > presented)
        if matching.contains(where: { $0.state == .mastered }) {
            return .mastered
        } else if matching.contains(where: { $0.state == .readyForAssessment }) {
            return .readyForAssessment
        } else if matching.contains(where: { $0.state == .practicing }) {
            return .practicing
        }
        return .presented
    }
    
    // MARK: - Computed Helpers
    
    /// Resolves the currently selected Lesson object from the provided list
    func lessonObject(from lessons: [Lesson]) -> Lesson? {
        lessons.first(where: { $0.id == editingLessonID })
    }
    
    /// Determines the next lesson in the group based on the current selection
    func nextLessonInGroup(from lessons: [Lesson]) -> Lesson? {
        guard let current = lessonObject(from: lessons) else { return nil }
        let actions = StudentLessonDetailActions()
        return actions.nextLessonInGroup(from: current, lessons: lessons)
    }

    // MARK: - Actions

    /// Applies local state to the persistent model without saving (useful for immediate updates)
    func applyEditsToModel(studentsAll: [Student], lessons: [Lesson], calendar: Calendar) {
        let actions = StudentLessonDetailActions()
        actions.applyEditsToModel(
            studentLesson: studentLesson,
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
    
    /// Saves changes to the database, handles lifecycle events, and auto-creates next lessons
    func save(
        studentsAll: [Student],
        lessons: [Lesson],
        lessonAssignmentsAll: [LessonAssignment],
        calendar: Calendar,
        onDone: (() -> Void)? = nil
    ) {
        // Capture prior presented state
        let wasGiven = studentLesson.isPresented || studentLesson.givenAt != nil

        // 1. Apply local edits to the model
        applyEditsToModel(studentsAll: studentsAll, lessons: lessons, calendar: calendar)

        // 2. Engagement Lifecycle (Record Presentation — work is created explicitly via workflow panel or pie menu)
        let nowGiven = isPresented || (givenAt != nil)
        if nowGiven {
            do {
                // Bridge: look up corresponding LessonAssignment for LifecycleService
                let slIDString = studentLesson.id.uuidString
                let laDesc = FetchDescriptor<LessonAssignment>(
                    predicate: #Predicate { $0.migratedFromStudentLessonID == slIDString }
                )
                if let la = try modelContext.fetch(laDesc).first {
                    let _ = try LifecycleService.recordPresentation(
                        from: la,
                        presentedAt: AppCalendar.startOfDay(givenAt ?? Date()),
                        modelContext: modelContext
                    )
                }
            } catch {
                Self.logger.debug("LifecycleService error: \(error)")
            }

            // Update mastery state on LessonPresentation records
            updateMasteryState(
                lessonID: studentLesson.lessonID,
                studentIDs: studentLesson.studentIDs,
                state: masteryState
            )

            // Auto-enroll students in track if lesson belongs to a track
            if let lesson = studentLesson.lesson {
                GroupTrackService.autoEnrollInTrackIfNeeded(
                    lesson: lesson,
                    studentIDs: studentLesson.studentIDs,
                    modelContext: modelContext,
                    saveCoordinator: saveCoordinator
                )
            }
        }

        // Auto-enroll when lesson is scheduled (if not already presented)
        if !nowGiven, studentLesson.scheduledFor != nil {
            if let lesson = studentLesson.lesson {
                GroupTrackService.autoEnrollInTrackIfNeeded(
                    lesson: lesson,
                    studentIDs: studentLesson.studentIDs,
                    modelContext: modelContext,
                    saveCoordinator: saveCoordinator
                )
            }
        }

        // 3. Auto-create next lesson if needed
        let actions = StudentLessonDetailActions()
        let nextLesson = nextLessonInGroup(from: lessons)
        
        actions.autoCreateNextIfNeeded(
            wasGiven: wasGiven,
            nowGiven: nowGiven,
            nextLesson: nextLesson,
            selectedStudentIDs: selectedStudentIDs,
            studentsAll: studentsAll,
            lessons: lessons,
            lessonAssignmentsAll: lessonAssignmentsAll,
            context: modelContext
        )

        // 4. Persist
        if saveCoordinator.save(modelContext, reason: "Saving student lesson") {
            // Reset autosave state
            notesAutosaveTask?.cancel()
            originalNotes = notes
            notesDirty = false

            // Notify system
            StudentLessonDetailUtilities.notifyInboxRefresh()

            onDone?()
        }
    }
    
    /// A lightweight save for autosaving notes or minor updates
    func saveImmediate(studentsAll: [Student], lessons: [Lesson], calendar: Calendar) {
        applyEditsToModel(studentsAll: studentsAll, lessons: lessons, calendar: calendar)
        saveCoordinator.save(modelContext, reason: "Auto-saving student lesson")
    }

    /// Deletes the student lesson
    func delete(onDone: (() -> Void)? = nil) {
        let id = studentLesson.id
        let ctx = modelContext
        let coordinator = saveCoordinator

        // Execute callback immediately to dismiss UI
        onDone?()

        // Perform deletion asynchronously
        Task { @MainActor in
            var desc = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.id == id })
            desc.fetchLimit = 1
            do {
                    if let toDelete = try ctx.fetch(desc).first {
                    // Access relationship to avoid faults before deletion
                    _ = toDelete.studentIDs
                    ctx.delete(toDelete)
                    coordinator.save(ctx, reason: "Deleting student lesson")
                }
            } catch {
                Self.logger.warning("Failed to fetch StudentLesson for deletion: \(error)")
            }
            StudentLessonDetailUtilities.notifyInboxRefresh()
        }
    }
    
    // MARK: - Special Logic
    
    /// Handles the "Move Students" action, creating a new lesson for them and removing them from this one
    func moveStudentsToInbox(
        studentsAll: [Student],
        lessonAssignmentsAll: [LessonAssignment],
        lessons: [Lesson]
    ) {
        guard !studentsToMove.isEmpty, let currentLesson = lessonObject(from: lessons) else { return }

        let actions = StudentLessonDetailActions()

        // Perform move using helper
        self.movedStudentNames = actions.moveStudentsToInbox(
            currentLesson: currentLesson,
            studentsToMove: studentsToMove,
            studentsAll: studentsAll,
            lessonAssignmentsAll: lessonAssignmentsAll,
            context: modelContext
        )
        
        // Remove students from current VM state
        selectedStudentIDs.subtract(studentsToMove)
        
        // Sync to model immediately so the view updates - convert UUIDs to strings for CloudKit compatibility
        let remainingUUIDs = Set(studentLesson.resolvedStudentIDs).subtracting(studentsToMove)
        studentLesson.studentIDs = remainingUUIDs.map { $0.uuidString }
        studentLesson.students = studentsAll.filter { remainingUUIDs.contains($0.id) }
        saveCoordinator.save(modelContext, reason: "Moving students to inbox")

        StudentLessonDetailUtilities.notifyInboxRefresh()

        // UI Updates
        studentsToMove.removeAll()
        showMovedBanner = true
        
        // Hide banner after delay
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: .seconds(3))
            showMovedBanner = false
        }
    }
    
    /// Reacts to changes in "Needs Another Presentation" toggle
    func handleNeedsAnotherChange(
        newValue: Bool,
        studentsAll: [Student],
        lessonAssignmentsAll: [LessonAssignment],
        lessons: [Lesson]
    ) {
        guard newValue else { return }
        guard !selectedStudentIDs.isEmpty else { return }

        // If toggled ON, ensure we create a fresh draft entry if one doesn't exist
        let sameStudents = Set(selectedStudentIDs)
        let exists = lessonAssignmentsAll.contains { la in
            la.resolvedLessonID == editingLessonID &&
            la.scheduledFor == nil &&
            !la.isPresented &&
            Set(la.resolvedStudentIDs) == sameStudents
        }

        if !exists {
            let newLA = PresentationFactory.makeDraft(
                lessonID: editingLessonID,
                studentIDs: Array(sameStudents)
            )
            PresentationFactory.attachRelationships(
                to: newLA,
                lesson: nil,
                students: studentsAll.filter { sameStudents.contains($0.id) }
            )
            modelContext.insert(newLA)
        }
    }
    
    /// Schedules a new presentation for the next lesson in the group
    func scheduleNextLessonToInbox(
        studentsAll: [Student],
        lessonAssignmentsAll: [LessonAssignment],
        lessons: [Lesson]
    ) {
        guard let next = nextLessonInGroup(from: lessons) else { return }
        guard !selectedStudentIDs.isEmpty else { return }

        let sameStudents = Set(selectedStudentIDs)

        // Avoid duplicates
        let exists = lessonAssignmentsAll.contains { la in
            la.resolvedLessonID == next.id && Set(la.resolvedStudentIDs) == sameStudents && !la.isPresented
        }
        if exists { return }

        let newLA = PresentationFactory.makeDraft(
            lessonID: next.id,
            studentIDs: Array(sameStudents)
        )
        PresentationFactory.attachRelationships(
            to: newLA,
            lesson: nil,
            students: studentsAll.filter { sameStudents.contains($0.id) }
        )
        modelContext.insert(newLA)
        saveCoordinator.save(modelContext, reason: "Scheduling next lesson")
        StudentLessonDetailUtilities.notifyInboxRefresh()
    }
    
    // MARK: - Notes Autosave
    
    private func scheduleNotesAutosave() {
        notesDirty = (notes != originalNotes)
        notesAutosaveTask?.cancel()
        
        guard notesDirty else { return }
        
        notesAutosaveTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(600)) // 0.6s debounce
            } catch {
                // Task was cancelled, exit early
                return
            }
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                // We need to fetch current snapshot of dependencies from the model or
                // ideally, we should just save the notes.
                // However, saveImmediate requires the arrays.
                // Since this runs in the VM context, we might not have the latest `studentsAll` if they changed.
                // But for notes, we generally only update the `notes` field.
                
                // NOTE: In a strictly pure VM, we'd need the View to trigger this.
                // For simplicity/safety in this refactor, we accept that 'applyEditsToModel'
                // might use the 'studentLesson.students' if we don't pass new ones.
                // But `applyEditsToModel` requires `studentsAll`.
                
                // To solve this properly in MVVM: The View should trigger the flush, or
                // we rely on the fact that `applyEditsToModel` is mainly updating the `StudentLesson` object
                // which is a class.
                
                // We will defer the actual persistent save to `flushNotesAutosaveIfNeeded`
                // called by the View, OR we set a flag.
                
                // However, the requirement is to move logic to VM.
                // We will signal the View or just let the `saveImmediate` happen via a closure provided by the View?
                // No, that's too complex.
                // We will update the `StudentLesson` object directly here.
                
                studentLesson.notes = notes
                saveCoordinator.save(modelContext, reason: "Auto-saving notes")

                originalNotes = notes
                notesDirty = false
                StudentLessonDetailUtilities.notifyInboxRefresh()
            }
        }
    }

    func flushNotesAutosaveIfNeeded() {
        notesAutosaveTask?.cancel()
        guard notesDirty else { return }

        studentLesson.notes = notes
        saveCoordinator.save(modelContext, reason: "Saving notes")

        originalNotes = notes
        notesDirty = false
        StudentLessonDetailUtilities.notifyInboxRefresh()
    }

    // MARK: - Mastery State Management

    /// Updates the mastery state on all LessonPresentation records for this lesson and students.
    private func updateMasteryState(
        lessonID: String,
        studentIDs: [String],
        state: LessonPresentationState
    ) {
        guard !studentIDs.isEmpty, !lessonID.isEmpty else { return }

        let allLessonPresentations = safeFetch(FetchDescriptor<LessonPresentation>())

        for studentID in studentIDs {
            if let existing = allLessonPresentations.first(where: { $0.lessonID == lessonID && $0.studentID == studentID }) {
                // Update existing record
                existing.state = state
                existing.lastObservedAt = Date()
                if state == .mastered && existing.masteredAt == nil {
                    existing.masteredAt = Date()
                } else if state != .mastered {
                    // If downgrading from mastered, clear masteredAt
                    existing.masteredAt = nil
                }
            } else {
                // Create new LessonPresentation if it doesn't exist
                let lp = LessonPresentation(
                    studentID: studentID,
                    lessonID: lessonID,
                    presentationID: nil,
                    state: state,
                    presentedAt: Date(),
                    lastObservedAt: Date(),
                    masteredAt: state == .mastered ? Date() : nil
                )
                modelContext.insert(lp)
            }
        }

        // If marking as mastered, check if track is now complete
        if state == .mastered, let lesson = studentLesson.lesson {
            for studentID in studentIDs {
                GroupTrackService.checkAndCompleteTrackIfNeeded(
                    lesson: lesson,
                    studentID: studentID,
                    modelContext: modelContext,
                    saveCoordinator: saveCoordinator
                )
            }
        }
    }
    
    // MARK: - Workflow Panel Management
    
    /// Enters workflow mode by initializing the presentation view model
    func enterWorkflowMode(students: [Student]) {
        presentationViewModel = PostPresentationFormViewModel(students: students)
        showWorkflowPanel = true
    }
    
    /// Exits workflow mode and cleans up the presentation view model
    func exitWorkflowMode() {
        presentationViewModel = nil
        showWorkflowPanel = false
    }
}
