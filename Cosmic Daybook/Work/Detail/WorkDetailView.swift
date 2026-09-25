import SwiftUI
import Combine
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
    #if DEBUG
    @FetchRequest(sortDescriptors: []) private var lessonAssignments: FetchedResults<CDLessonAssignment>
    #endif
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDWorkCheckIn.date, ascending: false)])
    var checkIns: FetchedResults<CDWorkCheckIn>
    // PERF: allLessons and allLessonAssignments moved into WorkDetailViewModel.loadWork()
    // to avoid loading entire tables via @Query. The ViewModel fetches only what's needed.
    #if DEBUG
    @FetchRequest(sortDescriptors: []) private var peerWorks: FetchedResults<CDWorkModel>
    #endif

    var likelyNextLesson: CDLesson? {
        viewModel.likelyNextLesson()
    }

    /// This work's practice sessions, newest first. Loaded on appear and
    /// whenever a practice session changes (see `reloadPracticeSessions`),
    /// instead of a live unfiltered `@FetchRequest` over every session whose
    /// transformable ids were decoded per session on every body pass.
    @State var practiceSessions: [CDPracticeSession] = []
    /// Size of the whole practice-session table at the last load; the
    /// participant lookup reloads when it moves, as it did on `.count` before.
    @State var practiceSessionTableCount: Int?

    /// The "Next Presentation" card's status. Two assignment fetches, so it is
    /// loaded on appear and when an assignment or work changes rather than on
    /// every body pass (which included every keystroke in the title field).
    @State var presentationStatus: WorkPresentationStatusService.PresentationStatus?

    // PERF: Uses ViewModel's cached resolvedLessonID/resolvedStudentID
    // instead of parsing UUID(uuidString:) on every body evaluation.
    var unlockInfo: (lessonID: UUID, studentID: UUID)? {
        guard viewModel.status == .mastered,
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
        viewModel = WorkDetailViewModel(workID: workID)

        let workIDString = workID.uuidString
        let scheduledStatus = WorkCheckInStatus.scheduled.rawValue
        _checkIns = FetchRequest(fetchRequest: {
            let request = CDFetchRequest(CDWorkCheckIn.self)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkCheckIn.date, ascending: false)]
            request.predicate = NSPredicate(
                format: "workID == %@ AND statusRaw == %@", workIDString, scheduledStatus
            )
            // Prefetch notes so each check-in row's note text reads from the row
            // cache instead of faulting the relationship per row (N+1).
            request.relationshipKeyPathsForPrefetching = ["notes"]
            return request
        }())
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
        .onReceive(
            NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: modelContext)
                .filter { !ManagedObjectChangeScope.touched(["PracticeSession"], in: $0.userInfo).isEmpty }
                .receive(on: DispatchQueue.main)
        ) { _ in
            reloadPracticeSessions()
        }
        .onPresentationDataChange(of: ["LessonAssignment", "WorkModel"], in: modelContext) { _ in
            reloadPresentationStatus()
        }
        .onAppear {
            viewModel.loadWork(modelContext: modelContext, saveCoordinator: saveCoordinator)
            reloadPracticeSessions()
            reloadPresentationStatus()
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

    /// The children and the work items this work's practice history names,
    /// fetched once for the whole section — see `loadPracticeParticipants`.
    @State var practiceStudents: [CDStudent] = []
    @State var practiceWorkItems: [CDWorkModel] = []

    @State var activeSheet: ActiveSheet?

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

                    let hasSteps = viewModel.work.map {
                        !($0.steps?.allObjects as? [CDWorkStep] ?? []).isEmpty
                    } ?? false
                    if hasSteps || viewModel.workKind == .report {
                        stepsSection()
                    }
                    if !practiceSessions.isEmpty { practiceOverviewSection() }
                    practiceHistorySection()
                    notesSection()
                    calendarSection()
                    groupMeetingSection()
                }.padding(AppTheme.Spacing.xlarge)
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
                        activeSheet = .addPractice
                    }

                    if showRepresentButton {
                        RoundedActionButton(
                            title: "Re-present",
                            icon: "arrow.clockwise",
                            color: .purple
                        ) {
                            activeSheet = .represent
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
        .sheet(item: $activeSheet) { sheet in
            sheetContent(for: sheet, work: work)
        }
        .alert("Delete?", isPresented: $viewModel.showDeleteAlert) {
            Button("Delete", role: .destructive) { deleteWork() }
        }
        .alert("Unlock Next Lesson?", isPresented: $viewModel.showUnlockNextLessonAlert) {
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
        .alert("Edit Note", isPresented: $viewModel.showEditNoteAlert) {
            TextField("Note", text: $viewModel.editingNoteDraft)
            Button("Save") {
                if let checkIn = viewModel.editingNoteCheckIn {
                    let trimmed = viewModel.editingNoteDraft.trimmed()
                    _ = checkIn.setLegacyNoteText(trimmed.isEmpty ? nil : trimmed, in: modelContext)
                    saveCoordinator.save(modelContext, reason: "Edit check-in note")
                    viewModel.loadWork(modelContext: modelContext, saveCoordinator: saveCoordinator)
                }
                viewModel.editingNoteCheckIn = nil
            }
            Button("Cancel", role: .cancel) { viewModel.editingNoteCheckIn = nil }
        }
    }
}

// MARK: - Sheet Types & Content

extension WorkDetailView {

    /// The one sheet the detail view can show at a time. The three alerts
    /// (delete, unlock next lesson, edit check-in note) stay on the view model.
    enum ActiveSheet: Identifiable {
        case practiceSession(CDPracticeSession)
        case peerWork(UUID)
        case represent
        case addNote
        case editNote(CDNote)
        case addPractice
        case addStep
        case editStep(CDWorkStep)
        case groupMeetingDate

        var id: String {
            switch self {
            case .practiceSession(let session): return "practiceSession_\(session.id?.uuidString ?? "nil")"
            case .peerWork(let workID): return "peerWork_\(workID.uuidString)"
            case .represent: return "represent"
            case .addNote: return "addNote"
            case .editNote(let note): return "editNote_\(note.id?.uuidString ?? "nil")"
            case .addPractice: return "addPractice"
            case .addStep: return "addStep"
            case .editStep(let step): return "editStep_\(step.id?.uuidString ?? "nil")"
            case .groupMeetingDate: return "groupMeetingDate"
            }
        }
    }

    @ViewBuilder
    func sheetContent(for sheet: ActiveSheet, work: CDWorkModel) -> some View {
        switch sheet {
        case .practiceSession(let session):
            practiceSessionDetailSheet(session: session)
        case .peerWork(let workID):
            WorkDetailView(workID: workID) { activeSheet = nil }
        case .represent:
            representSheet
        case .addNote:
            noteEditorSheet(work: work, note: nil)
        case .editNote(let note):
            noteEditorSheet(work: work, note: note)
        case .addPractice:
            PracticeSessionSheet(initialWorkItem: work) { _ in
                // Practice session saved - will automatically show in history
            }
        case .addStep:
            WorkStepEditorSheet(work: work, existingStep: nil) {
                // Step was added - force refresh
            }
        case .editStep(let step):
            WorkStepEditorSheet(work: work, existingStep: step) {
                activeSheet = nil
            }
        case .groupMeetingDate:
            groupMeetingDatePickerSheet(work: work)
        }
    }

    @ViewBuilder
    private var representSheet: some View {
        if let info = representSheetInfo {
            AddLessonToInboxSheet(student: info.student, preselectedLessonID: info.lessonID)
        }
    }

    private func noteEditorSheet(work: CDWorkModel, note: CDNote?) -> some View {
        UnifiedNoteEditor(
            context: .work(work),
            initialNote: note,
            onSave: { _ in
                // Reload notes after saving
                viewModel.loadWork(modelContext: modelContext, saveCoordinator: saveCoordinator)
                activeSheet = nil
            },
            onCancel: {
                activeSheet = nil
            }
        )
    }
}
