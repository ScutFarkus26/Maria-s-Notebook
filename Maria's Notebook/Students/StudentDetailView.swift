// StudentDetailView.swift

import OSLog
import SwiftData
import SwiftUI

struct StudentDetailView: View {
    private static let logger = Logger.students

    // MARK: - Inputs
    let student: Student
    var onDone: (() -> Void)?

    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SaveCoordinator.self) private var saveCoordinator

    private var repository: StudentRepository {
        StudentRepository(context: modelContext, saveCoordinator: saveCoordinator)
    }

    // MARK: - State
    @State private var vm: StudentDetailViewModel

    @State private var isEditing = false
    @State private var draftFirstName = ""
    @State private var draftLastName = ""
    @State private var draftNickname = ""
    @State private var draftBirthday = Date()
    @State private var draftLevel: Student.Level = .lower
    @State private var draftStartDate = Date()
    @State private var showDeleteAlert = false

    @AppStorage(UserDefaultsKeys.studentDetailViewActiveTab) private var selectedTab: StudentDetailTab = .overview

    @State private var selectedWorkID: UUID?
    @State private var workCache: [WorkModel] = []
    @State private var showAIPlanning = false

    private var lessonIDs: [UUID] { vm.lessons.map(\.id) }
    private var lessonAssignmentIDs: [UUID] { vm.lessonAssignments.map(\.id) }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
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
                workCache: $workCache,
                selectedWorkID: $selectedWorkID,
                lessonsByID: vm.lessonsByID,
                nextLessonsForStudent: vm.nextLessonsForStudent
            )
        case .meetings:
            StudentMeetingsTab(student: student)
                .padding(.top, 36)
        case .notes:
            // handled in body
            EmptyView()
        case .progress:
            StudentProgressTab(student: student)
                .padding(.top, 36)
        case .history:
            StudentHistoryTab(student: student)
                .padding(.top, 36)
        case .files:
            StudentFilesTab(student: student)
                .padding(.top, 36)
        }
    }

    private func fetchWorkForStudent() -> [WorkModel] {
        return vm.fetchWorkModelsForStudent(modelContext: modelContext)
    }

    @ViewBuilder
    private func lessonGiveSheet(for lesson: Lesson) -> some View {
        let newLA = vm.createDraftLessonAssignment(
            for: lesson, modelContext: modelContext, saveCoordinator: saveCoordinator
        )
        PresentationDetailView(lessonAssignment: newLA) {
            vm.selectedLessonForGive = nil
            vm.loadData(modelContext: modelContext)
        }
        .studentDetailSheetSizing()
    }

    private func handleCancelEdit() { isEditing = false }

    private func handleSaveEdit() {
        let fn = draftFirstName.trimmed()
        let ln = draftLastName.trimmed()
        guard !fn.isEmpty, !ln.isEmpty else { return }
        let nick = draftNickname.trimmed()
        repository.updateStudent(
            id: student.id,
            firstName: fn,
            lastName: ln,
            birthday: draftBirthday,
            nickname: nick.isEmpty ? "" : nick,
            level: draftLevel,
            dateStarted: draftStartDate
        )
        _ = repository.save(reason: "Edit student details")
        isEditing = false
    }

    private func handleEdit() {
        draftFirstName = student.firstName
        draftLastName = student.lastName
        draftNickname = student.nickname ?? ""
        draftBirthday = student.birthday
        draftLevel = student.level
        draftStartDate = student.dateStarted ?? Date()
        isEditing = true
    }

    private func handleDelete() { showDeleteAlert = true }

    private func handleDone() {
        if let onDone { onDone() } else { dismiss() }
    }

    private var headerRow: some View {
        HStack {
            Text("Student Info")
                .font(AppTheme.ScaledFont.titleSmall)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Button(action: { showAIPlanning = true }, label: {
                Label("Plan Lessons", systemImage: "sparkles")
                    .font(AppTheme.ScaledFont.captionSemibold)
            })
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
    }
    
    var body: some View {
        VStack(spacing: 0) {
            headerRow

            StudentDetailTabNavigation(selectedTab: $selectedTab)

            Divider().padding(.top, 8)

            if selectedTab == .notes {
                StudentNotesTab(student: student)
            } else if selectedTab == .progress || selectedTab == .history || selectedTab == .files {
                tabContent
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
            } else {
                ScrollView {
                    VStack(spacing: 28) {
                        tabContent
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 24)
                }
            }
        }
        .studentDetailMainSizing()
        .safeAreaInset(edge: .bottom) {
            StudentDetailBottomBar(
                isEditing: isEditing,
                selectedTab: selectedTab,
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
        .overlay(alignment: .top) {
            StudentDetailToastOverlay(message: vm.toastMessage)
        }
        .alert("Delete Student?", isPresented: $showDeleteAlert) {
            Button("Delete", role: .destructive) {
                do {
                    try repository.deleteStudent(id: student.id)
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
        .sheet(item: $vm.selectedLessonAssignmentForDetail) { la in
            PresentationDetailView(lessonAssignment: la) {
                vm.selectedLessonAssignmentForDetail = nil
            }
            .studentDetailSheetSizing()
        }
        .sheet(isPresented: Binding(
            get: { selectedWorkID != nil },
            set: { if !$0 { selectedWorkID = nil } }
        )) {
            if let workID = selectedWorkID,
               let workModel = modelContext.resolveWorkModel(from: workID) {
                WorkDetailView(workID: workModel.id) {
                    selectedWorkID = nil
                }
                .studentDetailSheetSizing()
            } else if selectedWorkID != nil {
                ContentUnavailableView("Work not found", systemImage: "exclamationmark.triangle")
            }
        }
        .sheet(isPresented: $showAIPlanning) {
            AIPlanningAssistantView(mode: .singleStudent(student.id))
        }
        .task {
            vm.loadData(modelContext: modelContext)
            workCache = fetchWorkForStudent()
        }
        .onChange(of: lessonIDs) { _, _ in
            vm.loadData(modelContext: modelContext)
            workCache = fetchWorkForStudent()
        }
        .onChange(of: lessonAssignmentIDs) { _, _ in
            vm.loadData(modelContext: modelContext)
            workCache = fetchWorkForStudent()
        }
    }

    init(student: Student, onDone: (() -> Void)? = nil) {
        self.student = student
        self.onDone = onDone
        _vm = State(wrappedValue: StudentDetailViewModel(
            student: student, dependencies: AppDependenciesKey.defaultValue
        ))
    }
}
