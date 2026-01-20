// StudentDetailView.swift

import SwiftUI
import SwiftData
import Combine

struct StudentDetailView: View {
    // MARK: - Inputs
    let student: Student
    var onDone: (() -> Void)? = nil

    // MARK: - Environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var saveCoordinator: SaveCoordinator

    // MARK: - State
    @StateObject private var vm: StudentDetailViewModel

    @State private var isEditing = false
    @State private var draftFirstName = ""
    @State private var draftLastName = ""
    @State private var draftNickname = ""
    @State private var draftBirthday = Date()
    @State private var draftLevel: Student.Level = .lower
    @State private var draftStartDate = Date()
    @State private var showDeleteAlert = false

    @AppStorage("StudentDetailView.activeTab") private var selectedTab: StudentDetailTab = .overview

    @State private var selectedWorkID: UUID? = nil
    @State private var workCache: [WorkModel] = []

    private var lessonIDs: [UUID] { vm.lessons.map(\.id) }
    private var studentLessonIDs: [UUID] { vm.studentLessons.map(\.id) }

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
        let newSL: StudentLesson = vm.createDraftStudentLesson(for: lesson, modelContext: modelContext, saveCoordinator: saveCoordinator)
        StudentLessonDetailView(studentLesson: newSL) {
            vm.selectedLessonForGive = nil
            vm.loadData(modelContext: modelContext)
        }
        .studentDetailSheetSizing()
    }

    private func handleCancelEdit() { isEditing = false }

    private func handleSaveEdit() {
        let fn = draftFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let ln = draftLastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fn.isEmpty, !ln.isEmpty else { return }
        let nick = draftNickname.trimmingCharacters(in: .whitespacesAndNewlines)
        student.firstName = fn
        student.lastName = ln
        student.nickname = nick.isEmpty ? nil : nick
        student.birthday = draftBirthday
        student.level = draftLevel
        student.dateStarted = draftStartDate
        _ = saveCoordinator.save(modelContext, reason: "Edit student details")
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

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Student Info")
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

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
                modelContext.delete(student)
                _ = saveCoordinator.save(modelContext, reason: "Delete student")
                if let onDone { onDone() } else { dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(item: $vm.selectedLessonForGive) { lesson in
            lessonGiveSheet(for: lesson)
        }
        .sheet(item: $vm.selectedStudentLessonForDetail) { sl in
            StudentLessonDetailView(studentLesson: sl) {
                vm.selectedStudentLessonForDetail = nil
            }
            .studentDetailSheetSizing()
        }
        .sheet(isPresented: Binding(
            get: { selectedWorkID != nil },
            set: { if !$0 { selectedWorkID = nil } }
        )) {
            if let workID = selectedWorkID {
                // Try to find WorkModel by id first (if already migrated)
                let workModelFetch = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == workID })
                if let workModel = try? modelContext.fetch(workModelFetch).first {
                    WorkDetailView(workID: workModel.id) {
                        selectedWorkID = nil
                    }
                    .studentDetailSheetSizing()
                } else {
                    // Fallback: try to find WorkModel by legacyContractID (if not yet migrated)
                    let legacyFetch = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.legacyContractID == workID })
                    if let workModel = try? modelContext.fetch(legacyFetch).first {
                        WorkDetailView(workID: workModel.id) {
                            selectedWorkID = nil
                        }
                        .studentDetailSheetSizing()
                    } else {
                        ContentUnavailableView("Work not found", systemImage: "exclamationmark.triangle")
                    }
                }
            }
        }
        .task {
            vm.loadData(modelContext: modelContext)
            workCache = fetchWorkForStudent()
        }
        .onChange(of: lessonIDs) { _, _ in
            vm.loadData(modelContext: modelContext)
            workCache = fetchWorkForStudent()
        }
        .onChange(of: studentLessonIDs) { _, _ in
            vm.loadData(modelContext: modelContext)
            workCache = fetchWorkForStudent()
        }
    }

    init(student: Student, onDone: (() -> Void)? = nil) {
        self.student = student
        self.onDone = onDone
        _vm = StateObject(wrappedValue: StudentDetailViewModel(student: student))
    }
}
