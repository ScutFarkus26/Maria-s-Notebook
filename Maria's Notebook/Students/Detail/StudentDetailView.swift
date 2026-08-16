// StudentDetailView.swift

import OSLog
import SwiftUI
import CoreData

struct StudentDetailView: View {
    private static let logger = Logger.students

    // MARK: - Inputs
    let student: CDStudent
    /// True when shown inside the students split view detail column
    /// (no sheet sizing; Done clears the selection via onDone).
    var isInline: Bool = false
    var onDone: (() -> Void)?

    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.managedObjectContext) private var managedObjectContext
    @Environment(SaveCoordinator.self) private var saveCoordinator
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    private var repository: StudentRepository {
        StudentRepository(context: managedObjectContext, saveCoordinator: saveCoordinator)
    }

    // MARK: - State
    @State private var vm: StudentDetailViewModel

    @State private var isEditing = false
    @State private var draftFirstName = ""
    @State private var draftLastName = ""
    @State private var draftNickname = ""
    @State private var draftBirthday = Date()
    @State private var draftLevel: CDStudent.Level = .lower
    @State private var draftStartDate = Date()
    @State private var draftEnrollmentStatus: CDStudent.EnrollmentStatus = .enrolled
    @State private var draftDateWithdrawn: Date?
    @State private var showDeleteAlert = false

    // The stored key is retained so existing installations migrate cleanly.
    // Its old tab values are translated into the four guide-facing sections.
    @AppStorage(UserDefaultsKeys.studentDetailViewActiveTab)
    private var selectedSectionRaw = StudentWorkspaceSection.overview.rawValue

    @State private var selectedWorkID: UUID?
    @State private var workCache: [CDWorkModel] = []
    @State private var showAIPlanning = false
    @State private var showQuickNote = false
    @State private var showDocuments = false
    @State private var showMeetingSession = false

    private var lessonIDs: [UUID] { vm.lessons.compactMap(\.id) }
    private var lessonAssignmentIDs: [UUID] { vm.lessonAssignments.compactMap(\.id) }

    private var selectedSection: StudentWorkspaceSection {
        StudentWorkspaceSection.migrating(storedValue: selectedSectionRaw)
    }

    private var selectedSectionBinding: Binding<StudentWorkspaceSection> {
        Binding(
            get: { selectedSection },
            set: { selectedSectionRaw = $0.rawValue }
        )
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .overview:
            StudentOverviewTab(
                student: student,
                isEditing: isEditing,
                draftFirstName: $draftFirstName,
                draftLastName: $draftLastName,
                draftNickname: $draftNickname,
                draftBirthday: $draftBirthday,
                draftLevel: $draftLevel,
                draftStartDate: $draftStartDate,
                draftEnrollmentStatus: $draftEnrollmentStatus,
                draftDateWithdrawn: $draftDateWithdrawn,
                workCache: $workCache,
                selectedWorkID: $selectedWorkID,
                lessonsByID: vm.lessonsByID,
                nextLessonsForStudent: vm.nextLessonsForStudent,
                onWorkChanged: { workCache = fetchWorkForStudent() }
            )
        case .observe:
            StudentObserveWorkspace(student: student)
        case .learning:
            StudentLearningWorkspace(student: student)
        case .meetings:
            StudentMeetingsTab(student: student)
                .padding(.top, 36)
        }
    }

    private func fetchWorkForStudent() -> [CDWorkModel] {
        return vm.fetchWorkModelsForStudent(viewContext: viewContext)
    }

    @ViewBuilder
    private func lessonGiveSheet(for lesson: CDLesson) -> some View {
        let newLA = vm.createDraftLessonAssignment(
            for: lesson, viewContext: viewContext, saveCoordinator: saveCoordinator
        )
        PresentationDetailView(lessonAssignment: newLA) {
            vm.selectedLessonForGive = nil
            vm.loadData(viewContext: viewContext)
        }
        .studentDetailSheetSizing()
    }

    private func handleCancelEdit() { isEditing = false }

    private func handleSaveEdit() {
        let fn = draftFirstName.trimmed()
        let ln = draftLastName.trimmed()
        guard !fn.isEmpty, !ln.isEmpty else { return }
        let nick = draftNickname.trimmed()
        guard let studentID = student.id else { return }
        repository.updateStudent(
            id: studentID,
            firstName: fn,
            lastName: ln,
            birthday: draftBirthday,
            nickname: nick.isEmpty ? "" : nick,
            level: draftLevel,
            dateStarted: draftStartDate,
            enrollmentStatus: draftEnrollmentStatus,
            dateWithdrawn: .some(draftDateWithdrawn)
        )
        _ = repository.save(reason: "Edit student details")
        isEditing = false
    }

    private func handleEdit() {
        // The editor is part of the Overview section, so editing from anywhere
        // else would otherwise show a commit bar with no form above it.
        selectedSectionRaw = StudentWorkspaceSection.overview.rawValue
        draftFirstName = student.firstName
        draftLastName = student.lastName
        draftNickname = student.nickname ?? ""
        draftBirthday = student.birthday ?? Date()
        draftLevel = student.level
        draftStartDate = student.dateStarted ?? Date()
        draftEnrollmentStatus = student.enrollmentStatus
        draftDateWithdrawn = student.dateWithdrawn
        isEditing = true
    }

    private func handleDelete() { showDeleteAlert = true }

    private func handleDone() {
        if let onDone { onDone() } else { dismiss() }
    }

    private func startMeeting() {
        guard let studentID = student.id else { return }
        #if os(macOS)
        openWindow(
            id: "MeetingSessionWindow",
            value: MeetingSessionWindowPayload(studentID: studentID, scheduledMeetingID: nil)
        )
        #else
        showMeetingSession = true
        #endif
    }

    private func openDocuments() {
        guard let studentID = student.id else { return }
        #if os(macOS)
        openWindow(id: "StudentDocumentsWindow", value: studentID)
        #else
        showDocuments = true
        #endif
    }

    private var headerRow: some View {
        StudentRecordHeader(
            student: student,
            isEditing: isEditing,
            onAddObservation: { showQuickNote = true },
            onStartMeeting: startMeeting,
            onPlanLessons: { showAIPlanning = true },
            onOpenDocuments: openDocuments,
            onEdit: handleEdit,
            onDelete: handleDelete
        )
    }

    var body: some View {
        sizedContent
        #if os(iOS)
        .safeAreaInset(edge: .bottom) {
            StudentDetailBottomBar(
                isEditing: isEditing,
                selectedSection: selectedSection,
                showDeleteAlert: $showDeleteAlert,
                draftFirstName: draftFirstName,
                draftLastName: draftLastName,
                onCancel: handleCancelEdit,
                onSave: handleSaveEdit,
                onEdit: handleEdit,
                onDelete: handleDelete,
                onDone: handleDone
            )
        }
        #else
        .safeAreaInset(edge: .bottom) {
            if isEditing {
                StudentEditActionBar(
                    canSave: !draftFirstName.trimmed().isEmpty && !draftLastName.trimmed().isEmpty,
                    onCancel: handleCancelEdit,
                    onSave: handleSaveEdit
                )
            }
        }
        #endif
        .overlay(alignment: .top) {
            StudentDetailToastOverlay(message: vm.toastMessage)
        }
        .alert("Delete Student?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                do {
                    guard let studentID = student.id else { return }
                    try repository.deleteStudent(id: studentID)
                } catch {
                    Self.logger.warning("Failed to delete student: \(error)")
                }
                if let onDone { onDone() } else { dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(item: $vm.selectedLessonForGive) { lesson in
            lessonGiveSheet(for: lesson)
        }
#if os(iOS)
        .sheet(item: $vm.selectedLessonAssignmentForDetail) { la in
            PresentationDetailView(lessonAssignment: la) {
                vm.selectedLessonAssignmentForDetail = nil
            }
            .studentDetailSheetSizing()
        }
#endif
#if os(iOS)
        .sheet(isPresented: Binding(
            get: { selectedWorkID != nil },
            set: { if !$0 { selectedWorkID = nil } }
        )) {
            if let workID = selectedWorkID,
               let workModel = viewContext.resolveWorkModel(from: workID) {
                WorkDetailView(workID: workModel.id ?? UUID()) {
                    selectedWorkID = nil
                }
                .studentDetailSheetSizing()
            } else if selectedWorkID != nil {
                ContentUnavailableView("Work not found", systemImage: "exclamationmark.triangle")
            }
        }
#endif
        .sheet(isPresented: $showAIPlanning) {
            AIPlanningAssistantView(mode: .singleStudent(student.id ?? UUID()))
        }
        .sheet(isPresented: $showQuickNote) {
            QuickNoteSheet(initialStudentID: student.id)
        }
        #if os(iOS)
        .sheet(isPresented: $showDocuments) {
            NavigationStack {
                StudentFilesTab(student: student)
                    .navigationTitle("Documents")
            }
        }
        .sheet(isPresented: $showMeetingSession) {
            if let studentID = student.id {
                ScheduledMeetingSessionSheet(studentID: studentID)
            }
        }
        #endif
        .task {
            vm.loadData(viewContext: viewContext)
            workCache = fetchWorkForStudent()
        }
        .onChange(of: lessonIDs) { _, _ in
            vm.loadData(viewContext: viewContext)
            workCache = fetchWorkForStudent()
        }
        .onChange(of: lessonAssignmentIDs) { _, _ in
            vm.loadData(viewContext: viewContext)
            workCache = fetchWorkForStudent()
        }
        #if os(macOS)
        .onChange(of: selectedWorkID) { _, workID in
            guard let workID else { return }
            openWindow(id: "WorkDetailWindow", value: workID)
            selectedWorkID = nil
        }
        .onChange(of: vm.selectedLessonAssignmentForDetail?.id) { _, _ in
            guard let lessonAssignmentID = vm.selectedLessonAssignmentForDetail?.id else { return }
            openWindow(id: "PresentationDetailWindow", value: lessonAssignmentID)
            vm.selectedLessonAssignmentForDetail = nil
        }
        #endif
    }

    @ViewBuilder
    private var sizedContent: some View {
        if isInline { mainContent } else { mainContent.studentDetailMainSizing() }
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            headerRow

            StudentWorkspaceSectionPicker(selectedSection: selectedSectionBinding)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 8)

            Divider().padding(.top, 8)

            if selectedSection == .overview || selectedSection == .meetings {
                ScrollView {
                    VStack(spacing: 28) {
                        sectionContent
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                }
            } else {
                sectionContent
            }
        }
    }

    init(student: CDStudent, isInline: Bool = false, onDone: (() -> Void)? = nil) {
        self.student = student
        self.isInline = isInline
        self.onDone = onDone
        _vm = State(wrappedValue: StudentDetailViewModel(
            student: student, dependencies: AppDependenciesKey.defaultValue
        ))
    }
}
