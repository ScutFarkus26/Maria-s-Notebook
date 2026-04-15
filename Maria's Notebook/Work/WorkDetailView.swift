import SwiftUI
import CoreData
import Foundation

/// Unified detail view for viewing and editing work items
/// Replaces: WorkModelDetailSheet, WorkDetailWindowContainer, WorkDetailContainerView
struct WorkDetailView: View {
    let workID: UUID
    var onDone: (() -> Void)?
    var showRepresentButton: Bool = false

    @Environment(\.dismiss) var dismiss
    @Environment(\.managedObjectContext) var modelContext
    @Environment(SaveCoordinator.self) var saveCoordinator

    @State var viewModel: WorkDetailViewModel
    @State var showingRepresentSheet: Bool = false
    #if DEBUG
    @FetchRequest(sortDescriptors: []) private var lessonAssignments: FetchedResults<CDLessonAssignment>
    #endif
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkCheckIn.date, ascending: false)]) var checkIns: FetchedResults<CDWorkCheckIn>
    @FetchRequest(sortDescriptors: []) private var allPracticeSessions: FetchedResults<CDPracticeSession>
    // PERF: allLessons and allLessonAssignments moved into WorkDetailViewModel.loadWork()
    // to avoid loading entire tables via @Query. The ViewModel fetches only what's needed.
    #if DEBUG
    @FetchRequest(sortDescriptors: []) private var peerWorks: FetchedResults<CDWorkModel>
    #endif

    var scheduleDates: WorkScheduleDates {
        viewModel.scheduleDates(checkIns: Array(checkIns))
    }

    var likelyNextLesson: CDLesson? {
        viewModel.likelyNextLesson()
    }

    var practiceSessions: [CDPracticeSession] {
        viewModel.practiceSessions(allSessions: Array(allPracticeSessions))
    }

    // PERF: Uses ViewModel's cached resolvedLessonID/resolvedStudentID
    // instead of parsing UUID(uuidString:) on every body evaluation.
    var unlockInfo: (lessonID: UUID, studentID: UUID)? {
        guard viewModel.status == .complete,
              let outcome = viewModel.completionOutcome,
              outcome == .proficient || outcome == .needsReview,
              let lessonID = viewModel.resolvedLessonID,
              let studentID = viewModel.resolvedStudentID else {
            return nil
        }
        return (lessonID, studentID)
    }

    var representSheetInfo: (student: CDStudent, lessonID: UUID)? {
        guard let student = viewModel.relatedStudent,
              let lessonID = viewModel.resolvedLessonID else {
            return nil
        }
        return (student, lessonID)
    }

    var unlockNextLessonInfo: (lessonID: UUID, studentID: UUID)? {
        guard let lessonID = viewModel.resolvedLessonID,
              let studentID = viewModel.resolvedStudentID else {
            return nil
        }
        return (lessonID, studentID)
    }

    init(workID: UUID, onDone: (() -> Void)? = nil, showRepresentButton: Bool = false) {
        self.workID = workID
        self.onDone = onDone
        self.showRepresentButton = showRepresentButton
        _viewModel = State(wrappedValue: WorkDetailViewModel(workID: workID))

        let workIDString = workID.uuidString
        let scheduledStatus = WorkCheckInStatus.scheduled.rawValue
        _checkIns = FetchRequest(
            sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkCheckIn.date, ascending: false)],
            predicate: NSPredicate(format: "workID == %@ AND statusRaw == %@", workIDString, scheduledStatus)
        )
        #if DEBUG
        // FetchRequest for peer works - will filter by lessonID after work is loaded
        _peerWorks = FetchRequest(sortDescriptors: [])
        #endif
    }

    var body: some View {
        Group {
            if let work = viewModel.work {
                mainContent(work: work)
            } else {
                ContentUnavailableView("Work not found", systemImage: "doc.questionmark")
                    #if os(macOS)
                    .frame(minWidth: 400, minHeight: 200)
                    #endif
            }
        }
        .onAppear {
            viewModel.loadWork(modelContext: modelContext, saveCoordinator: saveCoordinator)
            if viewModel.work != nil {
                #if DEBUG
                PerformanceLogger.logScreenLoad(
                    screenName: "WorkDetailView",
                    itemCounts: [
                        "lessons": viewModel.relatedLessons.count,
                        "students": viewModel.relatedStudent != nil ? 1 : 0,
                        "workModelNotes": viewModel.workModelNotes.count,
                        "lessonAssignments": lessonAssignments.count,
                        "checkIns": checkIns.count,
                        "peerWorks": peerWorks.count
                    ]
                )
                #endif
            }
        }
    }

    @State var selectedWorkID: UUID?
    @State var selectedPracticeSession: CDPracticeSession?
    @State var showGroupMeetingDatePicker: Bool = false

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    private func mainContent(work: CDWorkModel) -> some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    headerSection()

                    presentationContextSection()

                    peersSection()

                    nextPresentationStatusSection

                    if viewModel.status == .complete { completionSection() }
                    if let work = viewModel.work, !((work.steps?.allObjects as? [CDWorkStep]) ?? []).isEmpty || viewModel.workKind == .report {
                        stepsSection()
                    }
                    if !practiceSessions.isEmpty { practiceOverviewSection() }
                    practiceHistorySection()
                    notesSection()
                    calendarSection()
                    groupMeetingSection()
                }.padding(AppTheme.Spacing.xlarge)
            }
            .sheet(item: $selectedPracticeSession) { session in
                practiceSessionDetailSheet(session: session)
            }
            .sheet(item: peerWorkSheetBinding) { wrapper in
                WorkDetailView(workID: wrapper.id) { selectedWorkID = nil }
            }
            Divider()
            VStack(spacing: 12) {
                // Top row: Action buttons
                HStack(spacing: 12) {
                    IconActionButton(
                        icon: "trash",
                        color: .red,
                        backgroundColor: Color.red.opacity(UIConstants.OpacityConstants.light)
                    ) {
                        viewModel.showDeleteAlert = true
                    }

                    RoundedActionButton(
                        title: "Add Practice",
                        icon: "person.2.fill",
                        color: .blue
                    ) {
                        viewModel.showPracticeSessionSheet = true
                    }

                    if showRepresentButton {
                        RoundedActionButton(
                            title: "Re-present",
                            icon: "arrow.clockwise",
                            color: .purple
                        ) {
                            showingRepresentSheet = true
                        }
                    }

                    Spacer()
                }

                // Bottom row: Cancel and Save buttons
                SaveCancelButtons(onCancel: close, onSave: save)
            }
            .padding(AppTheme.Spacing.large)
            .background(.bar)
        }
        .sheet(isPresented: $showingRepresentSheet) {
            if let info = representSheetInfo {
                AddLessonToInboxSheet(student: info.student, preselectedLessonID: info.lessonID)
            }
        }
        .sheet(isPresented: $viewModel.showScheduleSheet) {
                    WorkModelScheduleNextLessonSheet(work: work) { viewModel.showPlannedBanner = true }
                }
                .sheet(isPresented: $viewModel.showAddNoteSheet) {
                    UnifiedNoteEditor(
                        context: .work(work),
                        initialNote: nil,
                        onSave: { _ in
                            // Reload notes after saving
                            viewModel.loadWork(modelContext: modelContext, saveCoordinator: saveCoordinator)
                            viewModel.showAddNoteSheet = false
                        },
                        onCancel: {
                            viewModel.showAddNoteSheet = false
                        }
                    )
                }
                .sheet(item: $viewModel.noteBeingEdited) { note in
                    UnifiedNoteEditor(
                        context: .work(work),
                        initialNote: note,
                        onSave: { _ in
                            // Reload notes after saving
                            viewModel.loadWork(modelContext: modelContext, saveCoordinator: saveCoordinator)
                            viewModel.noteBeingEdited = nil
                        },
                        onCancel: {
                            viewModel.noteBeingEdited = nil
                        }
                    )
                }
                .sheet(isPresented: $viewModel.showPracticeSessionSheet) {
                    PracticeSessionSheet(initialWorkItem: work) { _ in
                        // Practice session saved - will automatically show in history
                    }
                }
                .alert("Delete?", isPresented: $viewModel.showDeleteAlert) {
                    Button("Delete", role: .destructive) { deleteWork() }
                }
                .alert("Unlock Next CDLesson?", isPresented: $viewModel.showUnlockNextLessonAlert) {
                    Button("Unlock") {
                        unlockNextLesson()
                    }
                    Button("Not Yet", role: .cancel) { }
                } message: {
                    if let nextLesson = viewModel.nextLessonToUnlock {
                        let studentName = viewModel.relatedStudent?.firstName
                            ?? "this student"
                        Text("Ready to unlock \(nextLesson.name) for \(studentName)?")
                    }
                }
                .sheet(isPresented: $viewModel.showAddStepSheet) {
                    WorkStepEditorSheet(work: work, existingStep: nil) {
                        // Step was added - force refresh
                    }
                }
            .sheet(item: $viewModel.stepBeingEdited) { step in
                WorkStepEditorSheet(work: work, existingStep: step) {
                    viewModel.stepBeingEdited = nil
                }
            }
            .sheet(isPresented: $showGroupMeetingDatePicker) {
                groupMeetingDatePickerSheet(work: work)
            }
    }
}
