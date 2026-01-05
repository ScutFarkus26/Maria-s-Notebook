// StudentDetailView.swift
// A focused sheet for displaying a student's details and upcoming lessons

import SwiftUI
import SwiftData
import Combine
// Uses StudentChecklistViewModel

/// Detail sheet for a single student, with Overview, Checklist, History, Meetings, and Notes tabs.
/// This refactor adds comments, MARKs, and tiny local naming cleanups without altering behavior.
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
    
    // --- CHANGED CODE START ---
    // Make enum String-backed to support storage
    private enum StudentDetailTab: String { case overview, checklist, history, meetings, notes }
    
    // Use @AppStorage to persist selection across different students
    @AppStorage("StudentDetailView.activeTab") private var selectedTab: StudentDetailTab = .overview
    // --- CHANGED CODE END ---
    
    @State private var selectedContract: WorkContract? = nil

    // NEW: Cache contracts for student in state
    @State private var contractsCache: [WorkContract] = []

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

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

    // MARK: - Live computed caches from ViewModel
    private var lessons: [Lesson] { vm.lessons }
    private var studentLessonsRaw: [StudentLesson] { vm.studentLessons }
    private var lessonsByID: [UUID: Lesson] { vm.lessonsByID }
    private var studentLessonsByID: [UUID: StudentLesson] { vm.studentLessonsByID }
    private var nextLessonsForStudent: [StudentLessonSnapshot] { vm.nextLessonsForStudent }
    
    // Added filtered computed properties for student-specific data
    // Note: Now this is just an alias since ViewModel already filters
    private var studentLessonsAll: [StudentLesson] { vm.studentLessons }

    // Lightweight ID arrays to aid type-checker in onChange
    private var lessonIDs: [UUID] { vm.lessons.map(\.id) }
    private var studentLessonIDs: [UUID] { vm.studentLessons.map(\.id) }

    // MARK: - Derived
    private var levelColor: Color {
        switch student.level {
        case .upper: return .pink
        case .lower: return .blue
        }
    }

    private var formattedBirthday: String {
        return Self.birthdayFormatter.string(from: student.birthday)
    }

    private var ageDescription: String {
        AgeUtils.verboseAgeString(for: student.birthday)
    }

    private var initials: String {
        let parts = student.fullName.split(separator: " ")
        if parts.count >= 2 {
            let first = parts.first?.first.map(String.init) ?? ""
            let last = parts.last?.first.map(String.init) ?? ""
            return (first + last).uppercased()
        } else if let first = student.fullName.first {
            return String(first).uppercased()
        } else {
            return "?"
        }
    }

    private var plannedLessonIDs: Set<UUID> { vm.plannedLessonIDs }

    private var practiceLessonIDs: Set<UUID> { vm.contractSummary.practiceLessonIDs }
    private var followUpLessonIDs: Set<UUID> { vm.contractSummary.followUpLessonIDs }
    private var pendingWorkLessonIDs: Set<UUID> { vm.contractSummary.pendingLessonIDs }

    // Compatibility accessors (mapped to the same pending set)
    private var pendingPracticeLessonIDs: Set<UUID> { vm.contractSummary.pendingLessonIDs }
    private var pendingFollowUpLessonIDs: Set<UUID> { vm.contractSummary.pendingLessonIDs }

    private var masteredLessonIDs: Set<UUID> { vm.masteredLessonIDs }


    // MARK: - Tab content builders
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
                lessonsByID: lessonsByID,
                nextLessonsForStudent: nextLessonsForStudent
            )
        case .checklist:
            StudentChecklistTab(
                student: student,
                subjects: subjectsForChecklist,
                selectedSubject: selectedChecklistSubject,
                lessons: lessons,
                studentLessonsRaw: studentLessonsRaw,
                rowStatesByLesson: checklistVM.rowStatesByLesson,
                onSubjectSelected: { setSelectedChecklistSubject($0) },
                onTapScheduled: { lesson, row in
                    if let pid = row?.plannedItemID, let sl = vm.studentLessons.first(where: { $0.id == pid }) {
                        vm.selectedStudentLessonForDetail = sl
                    } else {
                        let draft = vm.createOrReuseNonGivenStudentLesson(for: lesson, modelContext: modelContext)
                        _ = saveCoordinator.save(modelContext, reason: "Create or reuse non-given student lesson")
                        vm.loadData(modelContext: modelContext)
                        vm.selectedStudentLessonForDetail = draft
                        checklistVM.recompute(for: vm.lessons, using: modelContext)
                    }
                },
                onTapPresented: { lesson, row in
                    if let presID = row?.presentationLogID, let sl = vm.studentLessons.first(where: { $0.id == presID }) {
                        vm.selectedStudentLessonForDetail = sl
                    } else {
                        let sl = vm.logPresentation(for: lesson, modelContext: modelContext)
                        _ = vm.ensureContract(for: lesson, presentationStudentLesson: sl, modelContext: modelContext)
                        _ = saveCoordinator.save(modelContext, reason: "Log presentation and ensure contract")
                        vm.loadData(modelContext: modelContext)
                    }
                },
                onTapActive: { lesson, row in
                    if let cid = row?.contractID, let c = vm.fetchContract(by: cid, modelContext: modelContext) {
                        selectedContract = c
                    } else if (row?.isPresented ?? false) {
                        if let c = vm.ensureContract(for: lesson, presentationStudentLesson: nil, modelContext: modelContext) {
                            _ = saveCoordinator.save(modelContext, reason: "Ensure contract from checklist")
                            selectedContract = c
                        }
                    }
                },
                onTapComplete: { lesson, row in
                    if let cid = row?.contractID, let c = vm.fetchContract(by: cid, modelContext: modelContext), c.status != .complete {
                        c.status = .complete
                        c.completedAt = AppCalendar.startOfDay(Date())
                        _ = saveCoordinator.save(modelContext, reason: "Complete contract from checklist")
                        checklistVM.recompute(for: vm.lessons, using: modelContext)
                    } else if (row?.isPresented ?? false) && row?.contractID == nil {
                        if let c = vm.ensureContract(for: lesson, presentationStudentLesson: nil, modelContext: modelContext) {
                            c.status = .complete
                            c.completedAt = AppCalendar.startOfDay(Date())
                            _ = saveCoordinator.save(modelContext, reason: "Create-and-complete contract from checklist")
                            checklistVM.recompute(for: vm.lessons, using: modelContext)
                        }
                    }
                }
            )
        case .history:
            historyPlaceholder
                .padding(.top, 36)
        case .meetings:
            StudentMeetingsTab(student: student)
                .padding(.top, 36)
        case .notes:
            // Handled in body to avoid ScrollView
            EmptyView()
        }
    }

    // MARK: - Helper functions (delegate to ViewModel)
    
    private func fetchContractsForStudent() -> [WorkContract] {
        return vm.fetchContractsForStudent(modelContext: modelContext)
    }
    
    @ViewBuilder
    private func lessonGiveSheet(for lesson: Lesson) -> some View {
        // Create a draft StudentLesson for this student and selected lesson
        // Note: createDraftStudentLesson already saves the context
        let newSL: StudentLesson = vm.createDraftStudentLesson(for: lesson, modelContext: modelContext)
        
        let detailView = StudentLessonDetailView(studentLesson: newSL) {
            vm.selectedLessonForGive = nil
            // Refresh data after the sheet is dismissed
            vm.loadData(modelContext: modelContext)
        }
        
        #if os(macOS)
        detailView
            .frame(minWidth: 720, minHeight: 640)
            .presentationSizingFitted()
        #else
        detailView
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #endif
    }
    
    @ViewBuilder
    private var bottomBarContent: some View {
        // Hide the bar if we're not editing and not on overview (only "Done" would show, which is redundant on iPad/Mac)
        if isEditing || selectedTab == .overview {
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Spacer()
                    if isEditing {
                        editingButtons
                    } else {
                        viewingButtons
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private var editingButtons: some View {
        Button("Cancel") {
            isEditing = false
        }
        Button("Save") {
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
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
        .disabled(draftFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
    
    @ViewBuilder
    private var viewingButtons: some View {
        // Only show Profile Edit/Delete controls if we are on the Overview tab
        if selectedTab == .overview {
            Button("Edit") {
                draftFirstName = student.firstName
                draftLastName = student.lastName
                draftNickname = student.nickname ?? ""
                draftBirthday = student.birthday
                draftLevel = student.level
                draftStartDate = student.dateStarted ?? Date()
                isEditing = true
            }
            
            Button("Delete", role: .destructive) {
                showDeleteAlert = true
            }
        }
        
        // "Done" is useful for closing the sheet on iPhone/iPad modal
        Button("Done") {
            if let onDone { onDone() } else { dismiss() }
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(.borderedProminent)
    }


    private static let birthdayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .none
        return df
    }()

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Student Info")
                    .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 18)

            // Top pill navigation (Overview / Checklist)
            #if os(iOS)
            Group {
                if horizontalSizeClass == .compact {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            PillButton(title: "Overview", isSelected: selectedTab == .overview) { selectedTab = .overview }
                            PillButton(title: "Checklist", isSelected: selectedTab == .checklist) { selectedTab = .checklist }
                            PillButton(title: "History", isSelected: selectedTab == .history) { selectedTab = .history }
                            PillButton(title: "Meetings", isSelected: selectedTab == .meetings) { selectedTab = .meetings }
                            PillButton(title: "Notes", isSelected: selectedTab == .notes) { selectedTab = .notes }
                        }
                        .padding(.horizontal, 12)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                } else {
                    HStack {
                        Spacer()
                        HStack(spacing: 12) {
                            PillButton(title: "Overview", isSelected: selectedTab == .overview) { selectedTab = .overview }
                            PillButton(title: "Checklist", isSelected: selectedTab == .checklist) { selectedTab = .checklist }
                            PillButton(title: "History", isSelected: selectedTab == .history) { selectedTab = .history }
                            PillButton(title: "Meetings", isSelected: selectedTab == .meetings) { selectedTab = .meetings }
                            PillButton(title: "Notes", isSelected: selectedTab == .notes) { selectedTab = .notes }
                        }
                        Spacer()
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                }
            }
            #else
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    PillButton(title: "Overview", isSelected: selectedTab == .overview) { selectedTab = .overview }
                    PillButton(title: "Checklist", isSelected: selectedTab == .checklist) { selectedTab = .checklist }
                    PillButton(title: "History", isSelected: selectedTab == .history) { selectedTab = .history }
                    PillButton(title: "Meetings", isSelected: selectedTab == .meetings) { selectedTab = .meetings }
                    PillButton(title: "Notes", isSelected: selectedTab == .notes) { selectedTab = .notes }
                }
                Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
            #endif

            Divider()
                .padding(.top, 8)

            if selectedTab == .notes {
                // The new Notes timeline has its own internal list, so we avoid the wrapping ScrollView
                StudentNotesTab(student: student)
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
#if os(macOS)
        .frame(minWidth: 860, minHeight: 640)
        .presentationSizingFitted()
#else
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
#endif
        .safeAreaInset(edge: .bottom) {
            bottomBarContent
        }
        .overlay(alignment: .top) {
            Group {
                if let message = vm.toastMessage {
                    Text(message)
                        .font(.system(size: AppTheme.FontSize.caption, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(Color.black.opacity(0.85))
                        )
                        .foregroundColor(.white)
                        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .padding(.top, 8)
                }
            }
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
            #if os(macOS)
            .frame(minWidth: 720, minHeight: 640)
            .presentationSizingFitted()
            #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .sheet(item: $selectedContract) { contract in
            WorkContractDetailSheet(contract: contract) {
                selectedContract = nil
            }
        #if os(macOS)
            .frame(minWidth: 720, minHeight: 640)
            .presentationSizingFitted()
        #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #endif
        }
        .task {
            vm.loadData(modelContext: modelContext)
            checklistVM.recompute(for: vm.lessons, using: modelContext)
            ensureChecklistSubjectSelection()
            contractsCache = fetchContractsForStudent()
            vm.updateContracts(contractsCache)
        }
        .onChange(of: lessonIDs) { _, _ in
            // Reload data when lessons change
            vm.loadData(modelContext: modelContext)
            checklistVM.recompute(for: vm.lessons, using: modelContext)
            ensureChecklistSubjectSelection()
            contractsCache = fetchContractsForStudent()
            vm.updateContracts(contractsCache)
        }
        .onChange(of: studentLessonIDs) { _, _ in
            // Reload data when student lessons change
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
            // Prefer Geometry if present, otherwise first
            if let geo = subjects.first(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Geometry") == .orderedSame }) {
                setSelectedChecklistSubject(geo)
            } else {
                setSelectedChecklistSubject(subjects.first)
            }
        }
    }

    /// Creates the detail view for a student. Keeps StateObject identity stable across sheet presentations.
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

    private var meetingsPlaceholder: some View {
        ContentUnavailableView {
            Label("Meetings", systemImage: "person.2")
        } description: {
            Text("This will show the student's meetings.")
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }
}

#Preview {
    let container = ModelContainer.preview
    let context = container.mainContext

    // Seed a sample student and minimal references used by the view
    let student = Student(firstName: "Ada", lastName: "Lovelace", birthday: Date(timeIntervalSince1970: 0), level: .upper)
    context.insert(student)
    return StudentDetailView(student: student)
        .previewEnvironment(using: container)
}

