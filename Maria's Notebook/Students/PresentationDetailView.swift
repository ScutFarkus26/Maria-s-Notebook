import OSLog
import SwiftData
import SwiftUI

private let logger = Logger.students

struct PresentationDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    // Live Queries
    @Query private var lessons: [Lesson]
    @Query private var studentsAllRaw: [Student]
    @Query private var lessonAssignmentsAll: [LessonAssignment]

    private var lessonIDs: [UUID] {
        lessons.map(\.id)
    }

    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Use uniqueByID to prevent SwiftUI crash on "Duplicate values for key"
    // Filter out test students when setting is disabled
    private var studentsAll: [Student] {
        TestStudentsFilter.filterVisible(
            studentsAllRaw.uniqueByID, show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    let lessonAssignment: LessonAssignment
    let autoFocusLessonPicker: Bool
    var onDone: (() -> Void)?

    // ViewModel is optional and initialized in onAppear
    @State private var vm: PresentationDetailViewModel?

    // Child ViewModel (LessonPicker)
    // We initialize it with a dummy state; it will be configured in onAppear
    @State private var lessonPickerVM = LessonPickerViewModel(selectedStudentIDs: [], selectedLessonID: UUID())

    init(lessonAssignment: LessonAssignment, onDone: (() -> Void)? = nil, autoFocusLessonPicker: Bool = false) {
        self.lessonAssignment = lessonAssignment
        self.onDone = onDone
        self.autoFocusLessonPicker = autoFocusLessonPicker
    }

    var body: some View {
        Group {
            if let vm {
                // Pass non-optional VM to the content view to enable Bindings
                PresentationDetailContentView(
                    vm: vm,
                    lessonPickerVM: lessonPickerVM,
                    lessons: lessons,
                    studentsAll: studentsAll,
                    lessonAssignmentsAll: lessonAssignmentsAll,
                    onDone: onDone
                )
            } else {
                ProgressView()
            }
        }
        .onAppear {
            if vm == nil {
                // Initialize Main VM
                let newVM = PresentationDetailViewModel(
                    lessonAssignment: lessonAssignment,
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
                    lessonAssignmentsAll: lessonAssignmentsAll,
                    lessons: lessons
                )
            }
        }
    }
}

// MARK: - Content Subview
/// Extracts the content so `vm` can be treated as non-optional for Bindings
struct PresentationDetailContentView: View {
    @Bindable var vm: PresentationDetailViewModel
    @Bindable var lessonPickerVM: LessonPickerViewModel

    let lessons: [Lesson]
    let studentsAll: [Student]
    let lessonAssignmentsAll: [LessonAssignment]
    let onDone: (() -> Void)?

    @Environment(\.dismiss) var dismiss
    @Environment(\.modelContext) var modelContext
    @Environment(\.calendar) var calendar
    @State var lessonPickerFocused: Bool = false
    @State var showUnsavedChangesAlert: Bool = false
    @State var showIndependentWorkflowWindow: Bool = false
    @State var triggerWorkflowCompletion: Bool = false

    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif

    var body: some View {
        Group {
            if vm.showWorkflowPanel {
                threePanelLayout
            } else {
                planningView
            }
        }
        .adaptiveAnimation(.easeInOut(duration: 0.3), value: vm.showWorkflowPanel)
        #if os(macOS)
        .frame(
            minWidth: vm.showWorkflowPanel ? 1400 : 720,
            idealWidth: vm.showWorkflowPanel ? 1600 : 720,
            minHeight: vm.showWorkflowPanel ? 700 : 800,
            idealHeight: vm.showWorkflowPanel ? 800 : 900
        )
        .background(
            SheetWindowResizer(
                targetSize: vm.showWorkflowPanel
                    ? NSSize(width: 1600, height: 800)
                    : NSSize(width: 720, height: 900)
            )
        )
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
                        proficiencyStatusRow
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

    // MARK: - Computed Properties

    var currentLessonName: String {
        vm.lessonObject(from: lessons)?.name ?? "Lesson"
    }

    var currentLessonID: UUID {
        vm.lessonObject(from: lessons)?.id ?? vm.editingLessonID
    }

    var currentLesson: Lesson? {
        vm.lessonObject(from: lessons)
    }

    var selectedStudentsList: [Student] {
        studentsAll
            .filter { vm.selectedStudentIDs.contains($0.id) }
            .sorted(by: StudentSortComparator.byFirstName)
    }

    #if os(iOS)
    var progressButtonsHorizontalPadding: CGFloat {
        horizontalSizeClass == .compact ? 16 : 32
    }
    #else
    var progressButtonsHorizontalPadding: CGFloat {
        32
    }
    #endif

    // MARK: - Helpers & Logic

    func handleDone() {
        if let onDone {
            onDone()
        } else {
            dismiss()
        }
    }

    func handleCancelWithCleanup() {
        // Cleanup empty drafts if cancelling
        if vm.lessonAssignment.studentIDs.isEmpty {
            modelContext.delete(vm.lessonAssignment)
            do {
                try modelContext.save()
            } catch {
                logger.warning("Failed to save after cancel cleanup: \(error)")
            }
        }
        handleDone()
    }

    func handleSaveAndDone() {
        vm.save(
            studentsAll: studentsAll,
            lessons: lessons,
            lessonAssignmentsAll: lessonAssignmentsAll,
            calendar: calendar
        ) {
            handleDone()
        }
    }
}
