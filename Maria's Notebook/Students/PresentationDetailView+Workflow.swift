import SwiftUI

// MARK: - Workflow Panel Components

extension PresentationDetailContentView {

    // MARK: - Three Panel Layout (Planning + Presentation + Work)

    @ViewBuilder
    var threePanelLayout: some View {
        if let presentationVM = vm.presentationViewModel {
            let lessonTitle = currentLessonName
            let lessonID = currentLessonID

            VStack(spacing: 0) {
                // Header toolbar
                workflowHeaderBar(
                    presentationVM: presentationVM,
                    lessonTitle: lessonTitle,
                    lessonID: lessonID
                )

                // Three-panel layout
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        // Left Panel: Planning View
                        VStack(spacing: 0) {
                            PlanningPanelHeader()

                            ScrollView {
                                PlanningContentSections(
                                    horizontalPadding: 24,
                                    lessonHeader: { lessonHeaderSection },
                                    lessonPicker: { lessonPickerOrChangeControl(horizontalPadding: 24) },
                                    studentPills: { studentPillsSection },
                                    inboxStatus: { inboxStatusSection },
                                    notes: { notesSection }
                                )
                            }
                        }
                        .frame(width: geometry.size.width * 0.28)
                        .background(Color.primary.opacity(0.01))

                        Divider()

                        // Middle + Right Panels: Presentation and Work Items (from UnifiedPresentationWorkflowPanel)
                        // The panel internally splits into presentation (left) and work items (right)
                        UnifiedPresentationWorkflowPanel(
                            presentationViewModel: presentationVM,
                            students: selectedStudentsList,
                            lessonName: lessonTitle,
                            lessonID: lessonID,
                            onComplete: handleWorkflowComplete,
                            onCancel: vm.exitWorkflowMode,
                            triggerCompletion: $triggerWorkflowCompletion
                        )
                        .frame(width: geometry.size.width * 0.72)
                    }
                }
            }
            .onKeyPress { press in
                // Handle Escape key
                if press.key == .escape {
                    vm.exitWorkflowMode()
                    return .handled
                }

                // Handle Cmd+1 through Cmd+5 for understanding levels
                if press.modifiers.contains(.command),
                   let keyChar = press.characters.first,
                   let level = Int(String(keyChar)),
                   (1...5).contains(level) {
                    applyUnderstandingToAll(level: level, presentationVM: presentationVM)
                    return .handled
                }

                return .ignored
            }
            .onSubmit {
                // Cmd+Return to complete & save
                if canCompleteWorkflow(presentationVM: presentationVM) {
                    triggerWorkflowCompletion = true
                }
            }
            .alert("Unsaved Changes", isPresented: $showUnsavedChangesAlert) {
                Button("Discard Changes", role: .destructive) {
                    vm.exitWorkflowMode()
                }
                Button("Continue Editing", role: .cancel) {}
            } message: {
                Text("You have unsaved changes in the workflow. Are you sure you want to go back?")
            }
        }
    }

    // MARK: - Workflow Header Bar

    @ViewBuilder
    func workflowHeaderBar(
        presentationVM: PostPresentationFormViewModel,
        lessonTitle: String,
        lessonID: UUID
    ) -> some View {
        #if os(macOS)
        WorkflowHeaderBar(
            lessonTitle: lessonTitle,
            onBack: checkAndExitWorkflowMode,
            onComplete: { triggerWorkflowCompletion = true },
            canComplete: canCompleteWorkflow(presentationVM: presentationVM),
            onPopOut: {
                popOutToIndependentWindow(
                    presentationVM: presentationVM,
                    lessonTitle: lessonTitle,
                    lessonID: lessonID,
                    selectedStudents: selectedStudentsList
                )
            }
        )
        #else
        WorkflowHeaderBar(
            lessonTitle: lessonTitle,
            onBack: checkAndExitWorkflowMode,
            onComplete: { triggerWorkflowCompletion = true },
            canComplete: canCompleteWorkflow(presentationVM: presentationVM)
        )
        #endif
    }

    // MARK: - Keyboard Shortcut Helper

    func applyUnderstandingToAll(level: Int, presentationVM: PostPresentationFormViewModel) {
        for student in selectedStudentsList where presentationVM.entries[student.id] != nil {
            presentationVM.entries[student.id]?.understandingLevel = level
        }
    }

    // MARK: - Unsaved Changes Check

    func checkAndExitWorkflowMode() {
        if workflowHasUnsavedChanges {
            showUnsavedChangesAlert = true
        } else {
            vm.exitWorkflowMode()
        }
    }

    var workflowHasUnsavedChanges: Bool {
        guard let presentationVM = vm.presentationViewModel else { return false }
        return presentationVM.entries.values.contains { entry in
            !entry.observation.isEmpty ||
            !entry.assignment.isEmpty ||
            entry.understandingLevel != 3
        } || !presentationVM.groupObservation.isEmpty
    }

    // MARK: - Pop Out to Independent Window

    #if os(macOS)
    func popOutToIndependentWindow(
        presentationVM: PostPresentationFormViewModel,
        lessonTitle: String,
        lessonID: UUID,
        selectedStudents: [Student]
    ) {
        // Show the independent window
        showIndependentWorkflowWindow = true

        // Exit the embedded workflow mode to return to planning view
        // The presentation view model is still held by vm, so the independent window can use it
        vm.showWorkflowPanel = false
    }
    #endif

    // MARK: - Workflow Completion

    func handleWorkflowComplete() {
        setPresentationState(isPresented: true, givenAt: calendar.startOfDay(for: Date()), needsAnother: false)
        saveAndExitWorkflow()
    }

    func saveAndExitWorkflow() {
        vm.save(
            studentsAll: studentsAll,
            lessons: lessons,
            lessonAssignmentsAll: lessonAssignmentsAll,
            calendar: calendar
        ) {
            vm.exitWorkflowMode()
            handleDone()
        }
    }

    func canCompleteWorkflow(presentationVM: PostPresentationFormViewModel) -> Bool {
        presentationVM.canDismiss
    }
}
