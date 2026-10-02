import SwiftUI
import CoreData

struct PresentationDetailView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    // Test student filtering
    @TestStudentVisibility private var testStudents

    @Environment(\.dependencies) private var dependencies

    // No live whole-table assignment query here any more: see LiveLessonAssignments.swift.

    private var lessons: [CDLesson] { dependencies.lessonCatalog.all }

    private var lessonIDs: [UUID] {
        lessons.compactMap(\.id)
    }

    private var studentsAll: [CDStudent] {
        TestStudentsFilter.filterVisible(
            dependencies.roster.all, show: testStudents.show,
            namesRaw: testStudents.namesRaw
        )
    }

    let lessonAssignment: CDLessonAssignment
    let autoFocusLessonPicker: Bool
    var onDone: (() -> Void)?

    // ViewModel and session are created in onAppear
    @State private var vm: PresentationDetailViewModel?
    @State private var session: PresentationSession?

    // Child ViewModel (LessonPicker)
    // We initialize it with a dummy state; it will be configured in onAppear
    @State private var lessonPickerVM = LessonPickerViewModel(selectedStudentIDs: [], selectedLessonID: UUID())

    init(lessonAssignment: CDLessonAssignment, onDone: (() -> Void)? = nil, autoFocusLessonPicker: Bool = false) {
        self.lessonAssignment = lessonAssignment
        self.onDone = onDone
        self.autoFocusLessonPicker = autoFocusLessonPicker
    }

    var body: some View {
        Group {
            if let vm, let session {
                // Pass non-optional models to the content view to enable Bindings
                PresentationDetailContentView(
                    vm: vm,
                    session: session,
                    lessonPickerVM: lessonPickerVM,
                    lessons: lessons,
                    studentsAll: studentsAll,
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
                    viewContext: viewContext,
                    saveCoordinator: saveCoordinator,
                    autoFocusLessonPicker: autoFocusLessonPicker
                )
                self.vm = newVM
                self.session = PresentationSession(presentationID: lessonAssignment.id ?? UUID())

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
    }
}

// MARK: - Content Subview
/// Extracts the content so `vm` can be treated as non-optional for Bindings.
///
/// One sheet, two beats: the planning view says who was there and records it;
/// the same sheet then turns into How It Went (`PresentationHowItWentView`).
struct PresentationDetailContentView: View {
    @Bindable var vm: PresentationDetailViewModel
    @Bindable var session: PresentationSession
    @Bindable var lessonPickerVM: LessonPickerViewModel

    let lessons: [CDLesson]
    let studentsAll: [CDStudent]
    let onDone: (() -> Void)?

    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.calendar) var calendar
    @Environment(\.dependencies) var dependencies
    @State var lessonPickerFocused: Bool = false
    @State var attendance: [UUID: AttendanceStatus] = [:]
    @State var masteredOn: [UUID: Date?] = [:]
    @State var showRescheduleSheet = false
    @State var showRecordDayPicker = false
    @State var recordPickedDay = AppCalendar.startOfDay(Date())
    @State var isSavingSession = false
    @State var errorMessage: String?

    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif

    var body: some View {
        Group {
            if session.phase == .howItWent, let lesson = currentLesson {
                howItWentContent(lesson: lesson)
            } else {
                planningView
            }
        }
        .adaptiveAnimation(.easeInOut(duration: 0.25), value: session.phase)
        #if os(macOS)
        .frame(minWidth: 680, idealWidth: 720, minHeight: 640, idealHeight: 860)
        .background(SheetWindowResizer(targetSize: NSSize(width: 720, height: 860)))
        #endif
        .workRetractionAlert(
            isPresented: workRetractionAlertIsPresented,
            message: workRetractionMessage,
            onRemove: {
                let plans = vm.pendingWorkRetraction
                vm.pendingWorkRetraction = []
                saveAndDone(retractingWork: plans)
            },
            onKeep: {
                vm.pendingWorkRetraction = []
                saveAndDone(retractingWork: [])
            },
            onCancel: { vm.pendingWorkRetraction = [] }
        )
        .alert("Couldn’t Save Presentation", isPresented: errorIsPresented) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "The presentation could not be saved.")
        }
        .onAppear {
            reopenHowItWentIfFollowing()
        }
        .onDisappear {
            // Closing the sheet mid-way acts as Later: nothing is lost, so
            // nothing needs confirming.
            if session.phase == .howItWent, !session.isFinished {
                saveLater(closing: false)
            }
        }
    }

    // MARK: - Planning View (beat one)

    private var planningView: some View {
        VStack(spacing: 0) {
            headerBand
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    lessonPickerIfNeeded
                    sequenceLine
                    if vm.isPresented {
                        studentPillsSection
                    } else {
                        whoWasThereSection
                    }
                    notesSection
                }
                .padding(.horizontal, contentPadding)
                .padding(.vertical, 22)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .dismissKeyboardOnScroll()
        }
        .safeAreaInset(edge: .bottom) { footer }
        .alert("Delete Presentation?", isPresented: $vm.showDeleteAlert) {
            Button("Delete", role: .destructive) {
                // Closed on the next turn, not inside the alert's own action:
                // a dismissal issued while the alert is still tearing itself
                // down is swallowed, and the window this was deleted from
                // stays open over a presentation that no longer exists.
                vm.delete { Task { handleDone() } }
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
        .sheet(isPresented: $showRescheduleSheet) {
            rescheduleSheet
        }
        .sheet(item: $vm.recapWorkSheetID) { workID in
            WorkDetailView(workID: workID) {
                vm.recapWorkSheetID = nil
                vm.recomputeSequenceRecap(
                    currentLesson: currentLesson,
                    students: selectedStudentsList
                )
            }
        }
        .onChange(of: vm.showingStudentPickerPopover) { _, isShowing in
            if !isShowing && lessonPickerFocused {
                lessonPickerFocused = false
            }
        }
        .onAppear {
            if vm.showLessonPicker { lessonPickerFocused = true }
            vm.recomputeSequenceRecap(currentLesson: currentLesson, students: selectedStudentsList)
            refreshAttendance()
            refreshMasteryNotes()
        }
        .onChange(of: vm.editingLessonID) { _, _ in
            vm.recomputeSequenceRecap(currentLesson: currentLesson, students: selectedStudentsList)
            refreshMasteryNotes()
        }
        .onChange(of: vm.selectedStudentIDs) { _, _ in
            vm.recomputeSequenceRecap(currentLesson: currentLesson, students: selectedStudentsList)
            refreshAttendance()
            refreshMasteryNotes()
        }
        .onChange(of: session.presentedDay) { _, _ in
            session.resetTouches()
            refreshAttendance()
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

    var currentLesson: CDLesson? {
        vm.lessonObject(from: lessons)
    }

    var selectedStudentsList: [CDStudent] {
        studentsAll
            .filter { guard let sid = $0.id else { return false }; return vm.selectedStudentIDs.contains(sid) }
            .sorted(by: StudentSortComparator.byFirstName)
    }

    var contentPadding: CGFloat {
        #if os(iOS)
        horizontalSizeClass == .compact ? 16 : 28
        #else
        28
        #endif
    }

    var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

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
            viewContext.delete(vm.lessonAssignment)
            dependencies.saveCoordinator.save(viewContext, reason: "Discard empty draft")
        }
        handleDone()
    }

    /// Ticks follow the day's attendance; a hand-made tick stays.
    func refreshAttendance() {
        guard !vm.isPresented else { return }
        attendance = viewContext.attendanceStatuses(
            for: Array(vm.selectedStudentIDs),
            on: session.presentedDay
        )
        let absent = Set(attendance.compactMap { $0.value == .absent ? $0.key : nil })
        session.syncRoster(planned: vm.selectedStudentIDs, absent: absent)
    }

    /// Which of the children already have a mastery mark on the lesson, for the tiles' note.
    func refreshMasteryNotes() {
        let dates = PresentationRecordIndex.masteryDates(
            lessonID: vm.editingLessonID.uuidString,
            studentIDs: vm.selectedStudentIDs.map(\.uuidString),
            in: viewContext
        )
        masteredOn = Dictionary(uniqueKeysWithValues: dates.compactMap { key, date in
            UUID(uuidString: key).map { ($0, date) }
        })
    }
}
