import SwiftUI
import SwiftData

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

struct StudentLessonDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    // Test student filtering
    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // Live Queries
    @Query private var lessons: [Lesson]
    @Query private var studentsAllRaw: [Student]
    @Query private var studentLessonsAll: [StudentLesson]
    
    private var lessonIDs: [UUID] {
        lessons.map { $0.id }
    }

    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Use uniqueByID to prevent SwiftUI crash on "Duplicate values for key"
    // Filter out test students when setting is disabled
    private var studentsAll: [Student] {
        TestStudentsFilter.filterVisible(studentsAllRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    let studentLesson: StudentLesson
    let autoFocusLessonPicker: Bool
    var onDone: (() -> Void)? = nil

    // ViewModel is optional and initialized in onAppear
    @State private var vm: StudentLessonDetailViewModel?

    // Child ViewModel (LessonPicker)
    // We initialize it with a dummy state; it will be configured in onAppear
    @StateObject private var lessonPickerVM = LessonPickerViewModel(selectedStudentIDs: [], selectedLessonID: UUID())

    init(studentLesson: StudentLesson, onDone: (() -> Void)? = nil, autoFocusLessonPicker: Bool = false) {
        self.studentLesson = studentLesson
        self.onDone = onDone
        self.autoFocusLessonPicker = autoFocusLessonPicker
    }

    var body: some View {
        Group {
            if let vm = vm {
                // Pass non-optional VM to the content view to enable Bindings
                StudentLessonDetailContentView(
                    vm: vm,
                    lessonPickerVM: lessonPickerVM,
                    lessons: lessons,
                    studentsAll: studentsAll,
                    studentLessonsAll: studentLessonsAll,
                    onDone: onDone
                )
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if vm == nil {
                // Initialize Main VM
                let newVM = StudentLessonDetailViewModel(
                    studentLesson: studentLesson,
                    modelContext: modelContext,
                    saveCoordinator: saveCoordinator,
                    autoFocusLessonPicker: autoFocusLessonPicker
                )
                self.vm = newVM
                
                // Configure Picker VM
                lessonPickerVM.configure(lessons: lessons, students: studentsAll)
                lessonPickerVM.selectLesson(newVM.editingLessonID)
            }
        }
        .onChange(of: lessonIDs) { _, _ in
            lessonPickerVM.configure(lessons: lessons, students: studentsAll)
        }
        .onChange(of: lessonPickerVM.selectedLessonID) { _, newValue in
            // Sync Picker -> Main VM
            if let newID = newValue, let vm = vm {
                vm.editingLessonID = newID
                vm.showLessonPicker = false
            }
        }
        .onChange(of: vm?.needsAnotherPresentation) { _, newValue in
            // Sync Main VM -> Logic
            if let val = newValue, let vm = vm {
                vm.handleNeedsAnotherChange(
                    newValue: val,
                    studentsAll: studentsAll,
                    studentLessonsAll: studentLessonsAll,
                    lessons: lessons
                )
            }
        }
    }
}

// MARK: - Independent Workflow Window

#if os(macOS)
struct IndependentWorkflowWindow: View {
    @ObservedObject var presentationViewModel: PostPresentationFormViewModel
    let students: [Student]
    let lessonName: String
    let lessonID: UUID
    let onComplete: () -> Void
    let onCancel: () -> Void
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("\(lessonName) Presentation Workflow")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                    onCancel()
                }
                .buttonStyle(.bordered)
                
                Button("Complete & Save") {
                    onComplete()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
            .background(.bar)
            
            Divider()
            
            // Workflow panel (just presentation + work items)
            UnifiedPresentationWorkflowPanel(
                presentationViewModel: presentationViewModel,
                students: students,
                lessonName: lessonName,
                lessonID: lessonID,
                onComplete: {
                    onComplete()
                    dismiss()
                },
                onCancel: {
                    dismiss()
                    onCancel()
                },
                triggerCompletion: nil
            )
        }
    }
}
#endif

// MARK: - Content Subview
/// Extracts the content so `vm` can be treated as non-optional for Bindings
struct StudentLessonDetailContentView: View {
    @Bindable var vm: StudentLessonDetailViewModel
    @ObservedObject var lessonPickerVM: LessonPickerViewModel
    
    let lessons: [Lesson]
    let studentsAll: [Student]
    let studentLessonsAll: [StudentLesson]
    let onDone: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @State private var lessonPickerFocused: Bool = false
    @State private var showUnsavedChangesAlert: Bool = false
    @State private var showIndependentWorkflowWindow: Bool = false
    
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        Group {
            if vm.showWorkflowPanel {
                threePanelLayout
            } else {
                planningView
            }
        }
        .animation(.easeInOut(duration: 0.3), value: vm.showWorkflowPanel)
        #if os(macOS)
        .frame(
            minWidth: vm.showWorkflowPanel ? 1400 : 720,
            idealWidth: vm.showWorkflowPanel ? 1600 : 720,
            minHeight: vm.showWorkflowPanel ? 700 : 800,
            idealHeight: vm.showWorkflowPanel ? 800 : 900
        )
        .onChange(of: vm.showWorkflowPanel) { _, isShowing in
            if isShowing {
                // Force window to resize when entering workflow mode
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if let window = NSApplication.shared.keyWindow {
                        let newSize = NSSize(width: 1600, height: 800)
                        window.setFrame(
                            NSRect(origin: window.frame.origin, size: newSize),
                            display: true,
                            animate: true
                        )
                    }
                }
            }
        }
        #endif
        #if os(macOS)
        .sheet(isPresented: $showIndependentWorkflowWindow) {
            if let presentationVM = vm.presentationViewModel {
                IndependentWorkflowWindow(
                    presentationViewModel: presentationVM,
                    students: studentsAll.filter { vm.selectedStudentIDs.contains($0.id) },
                    lessonName: vm.lessonObject(from: lessons)?.name ?? "Lesson",
                    lessonID: vm.lessonObject(from: lessons)?.id ?? vm.editingLessonID,
                    onComplete: {
                        handleWorkflowComplete()
                        showIndependentWorkflowWindow = false
                    },
                    onCancel: {
                        showIndependentWorkflowWindow = false
                    }
                )
                .frame(minWidth: 1400, idealWidth: 1600, minHeight: 700, idealHeight: 800)
            }
        }
        #endif
    }
    
    // MARK: - Planning View (Single Column)
    
    private var planningView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    // 1. Lesson Title & Tags Header
                    lessonHeaderSection
                        .padding(.horizontal, 32)
                        .padding(.top, 32)
                    
                    // 2. Conditional Lesson Picker
                    if vm.lessonObject(from: lessons) == nil || vm.showLessonPicker {
                        lessonPickerSection
                            .padding(.horizontal, 32)
                            .padding(.top, 16)
                    } else {
                        ChangeLessonControl(showLessonPicker: $vm.showLessonPicker)
                            .padding(.horizontal, 32)
                            .padding(.top, 8)
                    }
                    
                    // 3. Student Pills Block
                    studentPillsSection
                        .padding(.horizontal, 32)
                        .padding(.top, 20)
                    
                    Divider()
                        .padding(.horizontal, 32)
                        .padding(.vertical, 20)
                    
                    // 4. Inbox/Scheduling Status Row
                    inboxStatusSection
                        .padding(.horizontal, 32)
                    
                    Divider()
                        .padding(.horizontal, 32)
                        .padding(.vertical, 20)
                    
                    // 5. Notes Section
                    notesSection
                        .padding(.horizontal, 32)
                        .padding(.top, 24)
                        .padding(.bottom, 32)
                    
                    // 6. Progress buttons row
                    progressButtonsRow
                        .padding(.horizontal, progressButtonsHorizontalPadding)
                        .padding(.top, 16)

                    // 7. Mastery status row (only shown when presented)
                    if vm.isPresented {
                        masteryStatusRow
                            .padding(.horizontal, progressButtonsHorizontalPadding)
                            .padding(.top, 16)
                            .padding(.bottom, 24)
                    }
                }
            }
            .dismissKeyboardOnScroll()
        }
        .safeAreaInset(edge: .bottom) { bottomBar }
        .alert("Delete Presentation?", isPresented: $vm.showDeleteAlert) {
            Button("Delete", role: .destructive) {
                vm.delete { handleDone() }
            }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $vm.showingAddStudentSheet) {
            AddStudentView()
        }
        .overlay(alignment: .top) {
            if vm.showMovedBanner {
                MovedStudentsBanner(studentNames: vm.movedStudentNames)
            }
        }
        .sheet(isPresented: $vm.showingMoveStudentsSheet) {
            moveStudentsSheet
        }
        .onChange(of: vm.showingStudentPickerPopover) { _, isShowing in
            if !isShowing && lessonPickerFocused {
                lessonPickerFocused = false
            }
        }
        .onAppear {
            if vm.showLessonPicker { lessonPickerFocused = true }
        }
        .onDisappear {
            vm.flushNotesAutosaveIfNeeded()
        }
    }
    
    // MARK: - Three Panel Layout (Planning + Presentation + Work)
    
    private var threePanelLayout: some View {
        guard let presentationVM = vm.presentationViewModel else {
            return AnyView(EmptyView())
        }
        
        let selectedStudents = studentsAll.filter { vm.selectedStudentIDs.contains($0.id) }
        let lessonTitle = vm.lessonObject(from: lessons)?.name ?? "Lesson"
        let lessonID = vm.lessonObject(from: lessons)?.id ?? vm.editingLessonID
        
        return AnyView(
            VStack(spacing: 0) {
                // Header toolbar
                HStack {
                    Button {
                        checkAndExitWorkflowMode()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Text("\(lessonTitle) Presentation Workflow")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                    
                    Spacer()
                    
                    #if os(macOS)
                    Button {
                        popOutToIndependentWindow(
                            presentationVM: presentationVM,
                            lessonTitle: lessonTitle,
                            lessonID: lessonID,
                            selectedStudents: selectedStudents
                        )
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.forward.square")
                            Text("Pop Out")
                        }
                    }
                    .buttonStyle(.bordered)
                    .help("Open in independent window")
                    #endif
                    
                    Button("Complete & Save") {
                        handleWorkflowComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canCompleteWorkflow(presentationVM: presentationVM))
                }
                .padding()
                .background(.bar)
                
                Divider()
                
                // Three-panel layout
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        // Left Panel: Planning View
                        VStack(spacing: 0) {
                            // Header
                            VStack(spacing: 8) {
                                Text("Planning")
                                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .bold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(.bar)
                            
                            Divider()
                            
                            ScrollView {
                                VStack(spacing: 0) {
                                    // 1. Lesson Title & Tags Header
                                    lessonHeaderSection
                                        .padding(.horizontal, 24)
                                        .padding(.top, 24)
                                
                                // 2. Conditional Lesson Picker
                                if vm.lessonObject(from: lessons) == nil || vm.showLessonPicker {
                                    lessonPickerSection
                                        .padding(.horizontal, 24)
                                        .padding(.top, 16)
                                } else {
                                    ChangeLessonControl(showLessonPicker: $vm.showLessonPicker)
                                        .padding(.horizontal, 24)
                                        .padding(.top, 8)
                                }
                                
                                // 3. Student Pills Block
                                studentPillsSection
                                    .padding(.horizontal, 24)
                                    .padding(.top, 20)
                                
                                Divider()
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 20)
                                
                                // 4. Inbox/Scheduling Status Row
                                inboxStatusSection
                                    .padding(.horizontal, 24)
                                
                                Divider()
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 20)
                                
                                // 5. Notes Section
                                notesSection
                                    .padding(.horizontal, 24)
                                    .padding(.top, 24)
                                    .padding(.bottom, 32)
                                }
                            }
                        }
                        .frame(width: geometry.size.width * 0.28)
                        .background(Color.primary.opacity(0.01))
                        
                        Divider()
                        
                        // Middle + Right Panels: Presentation and Work Items (from UnifiedPresentationWorkflowPanel)
                        // The panel internally splits into presentation (left) and work items (right)
                        UnifiedPresentationWorkflowPanel(
                            presentationViewModel: presentationVM,
                            students: selectedStudents,
                            lessonName: lessonTitle,
                            lessonID: lessonID,
                            onComplete: { handleWorkflowComplete() },
                            onCancel: { vm.exitWorkflowMode() },
                            triggerCompletion: nil
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
                    handleWorkflowComplete()
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
        )
    }
    
    // Helper for keyboard shortcut
    private func applyUnderstandingToAll(level: Int, presentationVM: PostPresentationFormViewModel) {
        let selectedStudents = studentsAll.filter { vm.selectedStudentIDs.contains($0.id) }
        for student in selectedStudents {
            if presentationVM.entries[student.id] != nil {
                presentationVM.entries[student.id]?.understandingLevel = level
            }
        }
    }
    
    // Check for unsaved changes before exiting workflow
    private func checkAndExitWorkflowMode() {
        guard let presentationVM = vm.presentationViewModel else {
            vm.exitWorkflowMode()
            return
        }
        
        // Check if there are any changes (notes, observations, or understanding levels set)
        let hasChanges = presentationVM.entries.values.contains { entry in
            !entry.observation.isEmpty || 
            !entry.assignment.isEmpty || 
            entry.understandingLevel != 3 // 3 is default
        } || !presentationVM.groupObservation.isEmpty
        
        if hasChanges {
            showUnsavedChangesAlert = true
        } else {
            vm.exitWorkflowMode()
        }
    }
    
    // Pop out workflow to independent window
    #if os(macOS)
    private func popOutToIndependentWindow(
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
    
    // MARK: - Workflow Panel View (Embedded)
    
    private var workflowPanelView: some View {
        guard let presentationVM = vm.presentationViewModel else {
            return AnyView(EmptyView())
        }
        
        let selectedStudents = studentsAll.filter { vm.selectedStudentIDs.contains($0.id) }
        let lessonTitle = vm.lessonObject(from: lessons)?.name ?? "Lesson"
        let lessonID = vm.lessonObject(from: lessons)?.id ?? vm.editingLessonID
        
        return AnyView(
            VStack(spacing: 0) {
                // Header with back button and complete button
                HStack {
                    Button {
                        vm.exitWorkflowMode()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back to Planning")
                        }
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    Text("Presentation Workflow")
                        .font(.headline)
                    
                    Spacer()
                    
                    Button("Complete & Save") {
                        handleWorkflowComplete()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!presentationVM.canDismiss)
                }
                .padding()
                .background(.bar)
                
                Divider()
                
                // Embedded workflow panel
                UnifiedPresentationWorkflowPanel(
                    presentationViewModel: presentationVM,
                    students: selectedStudents,
                    lessonName: lessonTitle,
                    lessonID: lessonID,
                    onComplete: { handleWorkflowComplete() },
                    onCancel: { vm.exitWorkflowMode() },
                    triggerCompletion: nil
                )
            }
        )
    }
    
    private func handleWorkflowComplete() {
        // Sync state back to detail VM
        vm.isPresented = true
        vm.givenAt = calendar.startOfDay(for: Date())
        vm.needsAnotherPresentation = false
        
        // Save everything
        vm.save(
            studentsAll: studentsAll,
            lessons: lessons,
            studentLessonsAll: studentLessonsAll,
            calendar: calendar
        ) {
            // Exit workflow mode
            vm.exitWorkflowMode()
            
            // Optionally dismiss the entire detail view
            handleDone()
        }
    }
    
    // MARK: - Computed Properties
    
    #if os(iOS)
    private var progressButtonsHorizontalPadding: CGFloat {
        horizontalSizeClass == .compact ? 16 : 32
    }
    #else
    private var progressButtonsHorizontalPadding: CGFloat {
        32
    }
    #endif
    
    // MARK: - Sections
    
    private var lessonHeaderSection: some View {
        let lesson = vm.lessonObject(from: lessons)
        let hasFile: Bool = {
            guard let l = lesson else { return false }
            if let rel = l.pagesFileRelativePath, !rel.isEmpty { return true }
            return l.pagesFileBookmark != nil
        }()
        
        return StudentLessonHeaderView(
            lessonName: lesson?.name ?? "Lesson",
            subject: lesson?.subject ?? "",
            group: lesson?.group ?? "",
            subjectColor: AppColors.color(forSubject: lesson?.subject ?? ""),
            onTapTitle: hasFile ? { if let url = resolveLessonPagesURL() { openInPages(url) } } : nil
        )
    }
    
    private var studentPillsSection: some View {
        StudentPillsSection(
            students: selectedStudentsList,
            subjectColor: AppColors.color(forSubject: vm.lessonObject(from: lessons)?.subject ?? ""),
            onRemove: { id in vm.selectedStudentIDs.remove(id) },
            onOpenPicker: { vm.showingStudentPickerPopover = true },
            onOpenMove: {
                vm.studentsToMove = []
                vm.showingMoveStudentsSheet = true
            },
            canMoveStudents: selectedStudentsList.count > 1 && !vm.isPresented,
            onOpenMoveAbsent: { openMoveAbsentStudents() },
            canMoveAbsentStudents: canMoveAbsentStudents
        )
        .popover(isPresented: $vm.showingStudentPickerPopover, arrowEdge: .top) {
            StudentPickerPopover(
                students: studentsAll,
                selectedIDs: $vm.selectedStudentIDs,
                onDone: { vm.showingStudentPickerPopover = false }
            )
            .padding(12)
            .frame(minWidth: 320)
        }
    }
    
    private var inboxStatusSection: some View {
        InboxStatusSection(scheduledFor: $vm.scheduledFor)
    }
    
    private var notesSection: some View {
        StudentLessonNotesSectionUnified(
            studentLesson: vm.studentLesson,
            legacyNotes: $vm.notes,
            onLegacyNotesChange: { newNotes in
                vm.notes = newNotes
            }
        )
    }
    
    private var lessonPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            LessonPickerSection(
                viewModel: lessonPickerVM,
                resolvedLesson: lessons.first(where: { $0.id == lessonPickerVM.selectedLessonID }) ?? vm.lessonObject(from: lessons),
                isFocused: $lessonPickerFocused
            )
        }
    }
    
    @ViewBuilder
    private var progressButtonsRow: some View {
        #if os(iOS)
        if horizontalSizeClass == .compact {
            // iPhone: Stack buttons vertically
            HStack(spacing: 8) {
                Button { selectJustPresented() } label: {
                    StatePill(
                        title: "Just Presented",
                        systemImage: "checkmark.circle.fill",
                        tint: .green,
                        active: isJustPresentedActive
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                Button { selectPreviouslyPresented() } label: {
                    StatePill(
                        title: "Previously",
                        systemImage: "clock.badge.checkmark",
                        tint: .green,
                        active: isPreviouslyPresentedActive
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        } else {
            // iPad: Original horizontal layout
            HStack(spacing: 12) {
                Button { selectJustPresented() } label: {
                    StatePill(
                        title: "Just Presented",
                        systemImage: "checkmark.circle.fill",
                        tint: .green,
                        active: isJustPresentedActive
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)

                Button { selectPreviouslyPresented() } label: {
                    StatePill(
                        title: "Previously Presented",
                        systemImage: "clock.badge.checkmark",
                        tint: .green,
                        active: isPreviouslyPresentedActive
                    )
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
        }
        #else
        // macOS: Original horizontal layout
        HStack(spacing: 12) {
            Button { selectJustPresented() } label: {
                StatePill(
                    title: "Just Presented",
                    systemImage: "checkmark.circle.fill",
                    tint: .green,
                    active: isJustPresentedActive
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)

            Button { selectPreviouslyPresented() } label: {
                StatePill(
                    title: "Previously Presented",
                    systemImage: "clock.badge.checkmark",
                    tint: .green,
                    active: isPreviouslyPresentedActive
                )
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
        }
        #endif
    }
    
    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()
            Group {
                #if os(iOS)
                if horizontalSizeClass == .compact {
                    // iPhone: Stack buttons vertically for better touch targets
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            Button(role: .destructive) {
                                vm.showDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            .frame(maxWidth: .infinity)

                            Button("Cancel") {
                                // Cleanup empty drafts if cancelling
                                if vm.studentLesson.studentIDs.isEmpty {
                                    modelContext.delete(vm.studentLesson)
                                    try? modelContext.save()
                                }
                                handleDone()
                            }
                            .frame(maxWidth: .infinity)
                        }
                        
                        Button("Save") {
                            vm.save(
                                studentsAll: studentsAll,
                                lessons: lessons,
                                studentLessonsAll: studentLessonsAll,
                                calendar: calendar
                            ) {
                                handleDone()
                            }
                        }
                        .bold()
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                        .disabled(vm.selectedStudentIDs.isEmpty)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                } else {
                    // iPad: Original horizontal layout
                    HStack {
                        Button(role: .destructive) {
                            vm.showDeleteAlert = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Spacer()

                        Button("Cancel") {
                            // Cleanup empty drafts if cancelling
                            if vm.studentLesson.studentIDs.isEmpty {
                                modelContext.delete(vm.studentLesson)
                                try? modelContext.save()
                            }
                            handleDone()
                        }

                        Button("Save") {
                            vm.save(
                                studentsAll: studentsAll,
                                lessons: lessons,
                                studentLessonsAll: studentLessonsAll,
                                calendar: calendar
                            ) {
                                handleDone()
                            }
                        }
                        .bold()
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(vm.selectedStudentIDs.isEmpty)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                #else
                // macOS: Original horizontal layout
                HStack {
                    Button(role: .destructive) {
                        vm.showDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Spacer()

                    Button("Cancel") {
                        // Cleanup empty drafts if cancelling
                        if vm.studentLesson.studentIDs.isEmpty {
                            modelContext.delete(vm.studentLesson)
                            try? modelContext.save()
                        }
                        handleDone()
                    }

                    Button("Save") {
                        vm.save(
                            studentsAll: studentsAll,
                            lessons: lessons,
                            studentLessonsAll: studentLessonsAll,
                            calendar: calendar
                        ) {
                            handleDone()
                        }
                    }
                    .bold()
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(vm.selectedStudentIDs.isEmpty)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                #endif
            }
            .background(.bar)
        }
    }
    
    private var moveStudentsSheet: some View {
        MoveStudentsSheet(
            lessonName: vm.lessonObject(from: lessons)?.name ?? "Lesson",
            students: selectedStudentsList,
            studentsToMove: $vm.studentsToMove,
            selectedStudentIDs: vm.selectedStudentIDs,
            onMove: {
                vm.moveStudentsToInbox(
                    studentsAll: studentsAll,
                    studentLessonsAll: studentLessonsAll,
                    lessons: lessons
                )
                vm.showingMoveStudentsSheet = false
            },
            onCancel: {
                vm.studentsToMove = []
                vm.showingMoveStudentsSheet = false
            }
        )
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        .presentationSizingFitted()
        #endif
    }
    
    private var assignmentComposerSheet: some View {
        let selected = studentsAll.filter { vm.selectedStudentIDs.contains($0.id) }
        let lessonTitle = vm.lessonObject(from: lessons)?.name ?? "Lesson"
        let lessonID = vm.lessonObject(from: lessons)?.id ?? vm.editingLessonID

        return UnifiedPresentationWorkflowSheet(
            students: selected,
            lessonName: lessonTitle,
            lessonID: lessonID,
            onComplete: {
                // Work items are created by the workflow sheet
                // Update VM state to mark as presented
                vm.isPresented = true
                vm.givenAt = calendar.startOfDay(for: Date())
                vm.needsAnotherPresentation = false
                
                vm.showAssignmentComposer = false
                vm.save(
                    studentsAll: studentsAll,
                    lessons: lessons,
                    studentLessonsAll: studentLessonsAll,
                    calendar: calendar
                ) {
                    handleDone()
                }
            },
            onCancel: {
                // Reset status changes if user cancels
                vm.isPresented = vm.studentLesson.isPresented
                vm.givenAt = vm.studentLesson.givenAt
                vm.needsAnotherPresentation = vm.studentLesson.needsAnotherPresentation
                vm.showAssignmentComposer = false
            }
        )
    }

    // MARK: - Helpers & Logic
    
    private func handleDone() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }

    private var selectedStudentsList: [Student] {
        // studentsAll is already deduplicated, but filter first then sort for clarity
        studentsAll
            .filter { vm.selectedStudentIDs.contains($0.id) }
            .sorted(by: StudentSortComparator.byFirstName)
    }
    
    private func resolveLessonPagesURL() -> URL? {
        guard let lesson = vm.lessonObject(from: lessons) else { return nil }
        if let rel = lesson.pagesFileRelativePath, !rel.isEmpty, let url = try? LessonFileStorage.resolve(relativePath: rel) {
            return url
        }
        guard let bookmark = lesson.pagesFileBookmark else { return nil }
        var stale = false
        do {
#if os(macOS)
            let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
#else
            let url = try URL(resolvingBookmarkData: bookmark, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
#endif
            _ = url.startAccessingSecurityScopedResource()
            return url
        } catch {
            return nil
        }
    }
    
    private func openInPages(_ url: URL) {
        let needsAccess = url.startAccessingSecurityScopedResource()
        defer { if needsAccess { url.stopAccessingSecurityScopedResource() } }
#if os(iOS)
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
#elseif os(macOS)
        if let pagesAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iWork.Pages") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: pagesAppURL, configuration: config, completionHandler: nil)
        } else {
            NSWorkspace.shared.open(url)
        }
#endif
    }
    
    // MARK: - Mastery Status Row

    @ViewBuilder
    private var masteryStatusRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "star.circle")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 16))
                Text("Mastery Status")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }

            #if os(iOS)
            if horizontalSizeClass == .compact {
                // iPhone: Use full-width buttons in a vertical stack
                VStack(spacing: 8) {
                    Button { vm.masteryState = .presented } label: {
                        StatePill(
                            title: "Presented",
                            systemImage: "eye.fill",
                            tint: .blue,
                            active: vm.masteryState == .presented
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)

                    Button { vm.masteryState = .practicing } label: {
                        StatePill(
                            title: "Practicing",
                            systemImage: "arrow.triangle.2.circlepath",
                            tint: .purple,
                            active: vm.masteryState == .practicing
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)

                    Button { vm.masteryState = .mastered } label: {
                        StatePill(
                            title: "Mastered",
                            systemImage: "checkmark.seal.fill",
                            tint: .green,
                            active: vm.masteryState == .mastered
                        )
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                }
            } else {
                // iPad: Horizontal layout
                HStack(spacing: 12) {
                    Button { vm.masteryState = .presented } label: {
                        StatePill(
                            title: "Presented",
                            systemImage: "eye.fill",
                            tint: .blue,
                            active: vm.masteryState == .presented
                        )
                    }
                    .buttonStyle(.plain)

                    Button { vm.masteryState = .practicing } label: {
                        StatePill(
                            title: "Practicing",
                            systemImage: "arrow.triangle.2.circlepath",
                            tint: .purple,
                            active: vm.masteryState == .practicing
                        )
                    }
                    .buttonStyle(.plain)

                    Button { vm.masteryState = .mastered } label: {
                        StatePill(
                            title: "Mastered",
                            systemImage: "checkmark.seal.fill",
                            tint: .green,
                            active: vm.masteryState == .mastered
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }
            #else
            // macOS: Horizontal layout (unchanged)
            HStack(spacing: 12) {
                Button { vm.masteryState = .presented } label: {
                    StatePill(
                        title: "Presented",
                        systemImage: "eye.fill",
                        tint: .blue,
                        active: vm.masteryState == .presented
                    )
                }
                .buttonStyle(.plain)

                Button { vm.masteryState = .practicing } label: {
                    StatePill(
                        title: "Practicing",
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: .purple,
                        active: vm.masteryState == .practicing
                    )
                }
                .buttonStyle(.plain)

                Button { vm.masteryState = .mastered } label: {
                    StatePill(
                        title: "Mastered",
                        systemImage: "checkmark.seal.fill",
                        tint: .green,
                        active: vm.masteryState == .mastered
                    )
                }
                .buttonStyle(.plain)

                Spacer()
            }
            #endif
        }
        .padding(16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    // MARK: - Progress State Logic

    private var isJustPresentedActive: Bool {
        StudentLessonProgressHelper.isJustPresentedActive(
            isPresented: vm.isPresented,
            givenAt: vm.givenAt,
            calendar: calendar
        )
    }
    private var isPreviouslyPresentedActive: Bool {
        StudentLessonProgressHelper.isPreviouslyPresentedActive(
            isPresented: vm.isPresented,
            givenAt: vm.givenAt,
            calendar: calendar
        )
    }
    private var isNeedsAnotherActive: Bool {
        StudentLessonProgressHelper.isNeedsAnotherActive(
            needsAnotherPresentation: vm.needsAnotherPresentation,
            isPresented: vm.isPresented
        )
    }
    private func selectJustPresented() {
        vm.isPresented = true
        vm.givenAt = calendar.startOfDay(for: Date())
        vm.needsAnotherPresentation = false
        
        // Enter workflow mode instead of showing sheet
        let selectedStudents = studentsAll.filter { vm.selectedStudentIDs.contains($0.id) }
        vm.enterWorkflowMode(students: selectedStudents)
    }
    
    private func selectPreviouslyPresented() {
        vm.isPresented = true
        vm.needsAnotherPresentation = false
        if let date = vm.givenAt, calendar.isDateInToday(date) {
            vm.givenAt = nil
        }
        
        // Enter workflow mode instead of showing sheet
        let selectedStudents = studentsAll.filter { vm.selectedStudentIDs.contains($0.id) }
        vm.enterWorkflowMode(students: selectedStudents)
        vm.showAssignmentComposer = true
    }
    private func selectNeedsAnother() {
        vm.isPresented = false
        vm.givenAt = nil
        vm.needsAnotherPresentation = true
    }
    
    // MARK: - Assignments Logic

    private func createFollowUpAssignments(_ assignments: [PostPresentationAssignmentsSheet.AssignmentEntry]) {
        let lessonID = vm.lessonObject(from: lessons)?.id ?? vm.editingLessonID
        StudentLessonAssignmentService.createFollowUpAssignments(
            assignments,
            lessonID: lessonID,
            studentLessonsAll: studentLessonsAll,
            modelContext: modelContext
        )
    }



    // MARK: - Workflow Helpers
    
    private func canCompleteWorkflow(presentationVM: PostPresentationFormViewModel) -> Bool {
        // Must have valid presentation status
        return presentationVM.canDismiss
    }
    
    // MARK: - Absent Logic
    private var scheduledAttendanceDay: Date { AppCalendar.startOfDay(Date()) }

    private var absentStudentIDs: Set<UUID> {
        StudentLessonAbsentHelper.computeAbsentStudentIDs(
            selectedStudentIDs: vm.selectedStudentIDs,
            scheduledDay: scheduledAttendanceDay,
            modelContext: modelContext
        )
    }

    private var canMoveAbsentStudents: Bool {
        StudentLessonAbsentHelper.canMoveAbsentStudents(
            studentCount: selectedStudentsList.count,
            isPresented: vm.isPresented,
            absentStudentIDs: absentStudentIDs
        )
    }

    private func openMoveAbsentStudents() {
        let ids = absentStudentIDs
        guard !ids.isEmpty else { return }
        vm.studentsToMove = ids
        vm.showingMoveStudentsSheet = true
    }

    // MARK: - UI Components
    private struct StatePill: View {
        let title: String
        let systemImage: String
        let tint: Color
        var active: Bool = false
        var body: some View {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundStyle(tint)
            .background(
                Capsule(style: .continuous)
                    .fill(tint.opacity(active ? 0.20 : 0.10))
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
        }
    }
}
