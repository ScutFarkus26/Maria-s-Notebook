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
    @StateObject private var checklistVM: StudentChecklistViewModel

    @State private var isEditing = false
    @State private var draftFirstName = ""
    @State private var draftLastName = ""
    @State private var draftNickname = ""
    @State private var draftBirthday = Date()
    @State private var draftLevel: Student.Level = .lower
    @State private var draftStartDate = Date()
    @State private var showDeleteAlert = false

    @AppStorage("StudentDetailView.activeTab") private var selectedTab: StudentDetailTab = .overview

    @State private var selectedContract: WorkContract? = nil
    @State private var contractsCache: [WorkContract] = []

    @AppStorage("StudentDetailView.selectedChecklistSubject") private var selectedChecklistSubjectRaw: String = ""

    private var selectedChecklistSubject: String? {
        let s = selectedChecklistSubjectRaw.trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    private func setSelectedChecklistSubject(_ subject: String?) {
        let trimmed = subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        selectedChecklistSubjectRaw = trimmed
    }

    private let lessonsVM = LessonsViewModel()
    private var subjectsForChecklist: [String] {
        lessonsVM.subjects(from: vm.lessons)
    }

    private var lessonIDs: [UUID] { vm.lessons.map(\.id) }
    private var studentLessonIDs: [UUID] { vm.studentLessons.map(\.id) }

    private var checklistCoordinator: StudentChecklistTabCoordinator {
        StudentChecklistTabCoordinator(
            vm: vm,
            checklistVM: checklistVM,
            modelContext: modelContext,
            saveCoordinator: saveCoordinator,
            selectedContract: $selectedContract
        )
    }

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
                contractsCache: $contractsCache,
                selectedContract: $selectedContract,
                lessonsByID: vm.lessonsByID,
                nextLessonsForStudent: vm.nextLessonsForStudent
            )
        case .checklist:
            StudentChecklistTab(
                student: student,
                subjects: subjectsForChecklist,
                selectedSubject: selectedChecklistSubject,
                lessons: vm.lessons,
                studentLessonsRaw: vm.studentLessons,
                rowStatesByLesson: checklistVM.rowStatesByLesson,
                onSubjectSelected: { setSelectedChecklistSubject($0) },
                onTapScheduled: { lesson, row in checklistCoordinator.handleTapScheduled(lesson: lesson, row: row) },
                onTapPresented: { lesson, row in checklistCoordinator.handleTapPresented(lesson: lesson, row: row) },
                onTapActive: { lesson, row in checklistCoordinator.handleTapActive(lesson: lesson, row: row) },
                onTapComplete: { lesson, row in checklistCoordinator.handleTapComplete(lesson: lesson, row: row) }
            )
        case .history:
            historyPlaceholder
                .padding(.top, 36)
        case .meetings:
            StudentMeetingsTab(student: student)
                .padding(.top, 36)
        case .notes:
            // handled in body
            EmptyView()
        case .progress:
            StudentProgressTab(student: student)
        }
    }

    private func fetchContractsForStudent() -> [WorkContract] {
        vm.fetchContractsForStudent(modelContext: modelContext)
    }

    @ViewBuilder
    private func lessonGiveSheet(for lesson: Lesson) -> some View {
        let newSL: StudentLesson = vm.createDraftStudentLesson(for: lesson, modelContext: modelContext)
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
            } else if selectedTab == .progress {
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
        .sheet(item: $selectedContract) { contract in
            WorkContractDetailSheet(contract: contract) {
                selectedContract = nil
            }
            .studentDetailSheetSizing()
        }
        .task {
            vm.loadData(modelContext: modelContext)
            checklistVM.recompute(for: vm.lessons, using: modelContext)
            ensureChecklistSubjectSelection()
            contractsCache = fetchContractsForStudent()
            vm.updateContracts(contractsCache)
        }
        .onChange(of: lessonIDs) { _, _ in
            vm.loadData(modelContext: modelContext)
            checklistVM.recompute(for: vm.lessons, using: modelContext)
            ensureChecklistSubjectSelection()
            contractsCache = fetchContractsForStudent()
            vm.updateContracts(contractsCache)
        }
        .onChange(of: studentLessonIDs) { _, _ in
            vm.loadData(modelContext: modelContext)
            checklistVM.recompute(for: vm.lessons, using: modelContext)
            contractsCache = fetchContractsForStudent()
            vm.updateContracts(contractsCache)
        }
    }

    private func ensureChecklistSubjectSelection() {
        let subjects = subjectsForChecklist
        guard !subjects.isEmpty else {
            setSelectedChecklistSubject(nil)
            return
        }
        if let selected = selectedChecklistSubject,
           subjects.contains(where: { $0.caseInsensitiveCompare(selected) == .orderedSame }) {
            if let exact = subjects.first(where: { $0.caseInsensitiveCompare(selected) == .orderedSame }) {
                setSelectedChecklistSubject(exact)
            }
        } else {
            if let geo = subjects.first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Geometry") == .orderedSame }) {
                setSelectedChecklistSubject(geo)
            } else {
                setSelectedChecklistSubject(subjects.first)
            }
        }
    }

    init(student: Student, onDone: (() -> Void)? = nil) {
        self.student = student
        self.onDone = onDone
        _vm = StateObject(wrappedValue: StudentDetailViewModel(student: student))
        _checklistVM = StateObject(wrappedValue: StudentChecklistViewModel(studentID: student.id))
    }

    private var historyPlaceholder: some View {
        ContentUnavailableView {
            Label("History", systemImage: "clock.arrow.circlepath")
        } description: {
            Text("This will show the student's history.")
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}
