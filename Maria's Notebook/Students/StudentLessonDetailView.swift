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
    @State private var lessonPickerVM = LessonPickerViewModel(selectedStudentIDs: [], selectedLessonID: UUID())

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
    @Bindable var presentationViewModel: PostPresentationFormViewModel
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
    @Bindable var lessonPickerVM: LessonPickerViewModel
    
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
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
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
                    students: selectedStudentsList,
                    lessonName: currentLessonName,
                    lessonID: currentLessonID,
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
                    PlanningContentSections(
                        horizontalPadding: 32,
                        lessonHeader: { lessonHeaderSection },
                        lessonPicker: { lessonPickerOrChangeControl(horizontalPadding: 32) },
                        studentPills: { studentPillsSection },
                        inboxStatus: { inboxStatusSection },
                        notes: { notesSection }
                    )
                    
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

        let lessonTitle = currentLessonName
        let lessonID = currentLessonID
        
        return AnyView(
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
        for student in selectedStudentsList {
            if presentationVM.entries[student.id] != nil {
                presentationVM.entries[student.id]?.understandingLevel = level
            }
        }
    }

    // Check for unsaved changes before exiting workflow
    private func checkAndExitWorkflowMode() {
        if workflowHasUnsavedChanges {
            showUnsavedChangesAlert = true
        } else {
            vm.exitWorkflowMode()
        }
    }

    private var workflowHasUnsavedChanges: Bool {
        guard let presentationVM = vm.presentationViewModel else { return false }
        return presentationVM.entries.values.contains { entry in
            !entry.observation.isEmpty ||
            !entry.assignment.isEmpty ||
            entry.understandingLevel != 3
        } || !presentationVM.groupObservation.isEmpty
    }

    @ViewBuilder
    private func workflowHeaderBar(
        presentationVM: PostPresentationFormViewModel,
        lessonTitle: String,
        lessonID: UUID
    ) -> some View {
        #if os(macOS)
        WorkflowHeaderBar(
            lessonTitle: lessonTitle,
            onBack: checkAndExitWorkflowMode,
            onComplete: handleWorkflowComplete,
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
            onComplete: handleWorkflowComplete,
            canComplete: canCompleteWorkflow(presentationVM: presentationVM)
        )
        #endif
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


    private func handleWorkflowComplete() {
        setPresentationState(isPresented: true, givenAt: calendar.startOfDay(for: Date()), needsAnother: false)
        saveAndExitWorkflow()
    }

    private func saveAndExitWorkflow() {
        vm.save(
            studentsAll: studentsAll,
            lessons: lessons,
            studentLessonsAll: studentLessonsAll,
            calendar: calendar
        ) {
            vm.exitWorkflowMode()
            handleDone()
        }
    }
    
    // MARK: - Computed Properties

    private var currentLessonName: String {
        vm.lessonObject(from: lessons)?.name ?? "Lesson"
    }

    private var currentLessonID: UUID {
        vm.lessonObject(from: lessons)?.id ?? vm.editingLessonID
    }

    private var currentLesson: Lesson? {
        vm.lessonObject(from: lessons)
    }

    private var selectedStudentsList: [Student] {
        studentsAll
            .filter { vm.selectedStudentIDs.contains($0.id) }
            .sorted(by: StudentSortComparator.byFirstName)
    }

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
        StudentLessonHeaderView(
            lessonName: currentLesson?.name ?? "Lesson",
            subject: currentLesson?.subject ?? "",
            group: currentLesson?.group ?? "",
            subjectColor: AppColors.color(forSubject: currentLesson?.subject ?? ""),
            onTapTitle: lessonHasFile ? ({ openLessonFile() }) : nil
        )
    }

    private var lessonHasFile: Bool {
        guard let lesson = currentLesson else { return false }
        if let rel = lesson.pagesFileRelativePath, !rel.isEmpty { return true }
        return lesson.pagesFileBookmark != nil
    }

    private func openLessonFile() {
        if let url = resolveLessonPagesURL() {
            openInPages(url)
        }
    }
    
    private var studentPillsSection: some View {
        StudentPillsSection(
            students: selectedStudentsList,
            subjectColor: AppColors.color(forSubject: currentLesson?.subject ?? ""),
            onRemove: { id in vm.selectedStudentIDs.remove(id) },
            onOpenPicker: { vm.showingStudentPickerPopover = true },
            onOpenMove: openMoveStudentsSheet,
            canMoveStudents: selectedStudentsList.count > 1 && !vm.isPresented,
            onOpenMoveAbsent: openMoveAbsentStudents,
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

    private func openMoveStudentsSheet() {
        vm.studentsToMove = []
        vm.showingMoveStudentsSheet = true
    }
    
    private var inboxStatusSection: some View {
        InboxStatusSection(scheduledFor: $vm.scheduledFor)
    }
    
    private var notesSection: some View {
        StudentLessonNotesSectionUnified(
            studentLesson: vm.studentLesson,
            legacyNotes: $vm.notes,
            onLegacyNotesChange: { vm.notes = $0 }
        )
    }

    @ViewBuilder
    private func lessonPickerOrChangeControl(horizontalPadding: CGFloat) -> some View {
        if currentLesson == nil || vm.showLessonPicker {
            VStack(alignment: .leading, spacing: 8) {
                LessonPickerSection(
                    viewModel: lessonPickerVM,
                    resolvedLesson: lessons.first(where: { $0.id == lessonPickerVM.selectedLessonID }) ?? currentLesson,
                    isFocused: $lessonPickerFocused
                )
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.top, 16)
        } else {
            ChangeLessonControl(showLessonPicker: $vm.showLessonPicker)
                .padding(.horizontal, horizontalPadding)
                .padding(.top, 8)
        }
    }
    
    private var progressButtonsRow: some View {
        ProgressStateRow(
            onJustPresented: selectJustPresented,
            onPreviouslyPresented: selectPreviouslyPresented,
            isJustPresentedActive: isJustPresentedActive,
            isPreviouslyPresentedActive: isPreviouslyPresentedActive
        )
    }
    
    private var bottomBar: some View {
        StudentLessonBottomBar(
            onDelete: { vm.showDeleteAlert = true },
            onCancel: handleCancelWithCleanup,
            onSave: handleSaveAndDone,
            isSaveDisabled: vm.selectedStudentIDs.isEmpty
        )
    }
    
    private var moveStudentsSheet: some View {
        MoveStudentsSheet(
            lessonName: currentLessonName,
            students: selectedStudentsList,
            studentsToMove: $vm.studentsToMove,
            selectedStudentIDs: vm.selectedStudentIDs,
            onMove: handleMoveStudents,
            onCancel: cancelMoveStudents
        )
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        .presentationSizingFitted()
        #endif
    }

    private func handleMoveStudents() {
        vm.moveStudentsToInbox(
            studentsAll: studentsAll,
            studentLessonsAll: studentLessonsAll,
            lessons: lessons
        )
        vm.showingMoveStudentsSheet = false
    }

    private func cancelMoveStudents() {
        vm.studentsToMove = []
        vm.showingMoveStudentsSheet = false
    }


    // MARK: - Helpers & Logic
    
    private func handleDone() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }
    
    private func handleCancelWithCleanup() {
        // Cleanup empty drafts if cancelling
        if vm.studentLesson.studentIDs.isEmpty {
            modelContext.delete(vm.studentLesson)
            try? modelContext.save()
        }
        handleDone()
    }
    
    private func handleSaveAndDone() {
        vm.save(
            studentsAll: studentsAll,
            lessons: lessons,
            studentLessonsAll: studentLessonsAll,
            calendar: calendar
        ) {
            handleDone()
        }
    }

    private func resolveLessonPagesURL() -> URL? {
        guard let lesson = currentLesson else { return nil }

        // Try relative path first
        if let relativePath = lesson.pagesFileRelativePath, !relativePath.isEmpty,
           let url = try? LessonFileStorage.resolve(relativePath: relativePath) {
            return url
        }

        // Fallback to bookmark
        return resolveBookmarkURL(lesson.pagesFileBookmark)
    }

    private func resolveBookmarkURL(_ bookmark: Data?) -> URL? {
        guard let bookmark = bookmark else { return nil }
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
        openInPagesOnMac(url)
#endif
    }

#if os(macOS)
    private func openInPagesOnMac(_ url: URL) {
        if let pagesAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iWork.Pages") {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: pagesAppURL, configuration: config, completionHandler: nil)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
#endif
    
    // MARK: - Mastery Status Row

    private var masteryStatusRow: some View {
        MasteryStateRow(masteryState: $vm.masteryState)
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

    private func selectJustPresented() {
        setPresentationState(isPresented: true, givenAt: calendar.startOfDay(for: Date()), needsAnother: false)
        vm.enterWorkflowMode(students: selectedStudentsList)
    }

    private func selectPreviouslyPresented() {
        let givenAt = vm.givenAt.flatMap { calendar.isDateInToday($0) ? nil : $0 }
        setPresentationState(isPresented: true, givenAt: givenAt, needsAnother: false)
        vm.enterWorkflowMode(students: selectedStudentsList)
        vm.showAssignmentComposer = true
    }

    private func setPresentationState(isPresented: Bool, givenAt: Date?, needsAnother: Bool) {
        vm.isPresented = isPresented
        vm.givenAt = givenAt
        vm.needsAnotherPresentation = needsAnother
    }

    private func canCompleteWorkflow(presentationVM: PostPresentationFormViewModel) -> Bool {
        presentationVM.canDismiss
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
        guard !absentStudentIDs.isEmpty else { return }
        vm.studentsToMove = absentStudentIDs
        vm.showingMoveStudentsSheet = true
    }
}
