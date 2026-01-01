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
    @State private var draftBirthday = Date()
    @State private var draftLevel: Student.Level = .lower
    @State private var draftStartDate = Date()
    @State private var showDeleteAlert = false
    private enum StudentDetailTab { case overview, checklist, history, meetings, notes }
    @State private var selectedTab: StudentDetailTab = .overview
    @State private var selectedContract: WorkContract? = nil

    // NEW: Cache contracts for student in state
    @State private var contractsCache: [WorkContract] = []

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @AppStorage("StudentDetailView.selectedChecklistSubject") private var selectedChecklistSubjectRaw: String = ""

    // MARK: - Queries
    @Query private var lessons: [Lesson]
    @Query(sort: [
        SortDescriptor(\StudentLesson.scheduledFor, order: .forward),
        SortDescriptor(\StudentLesson.createdAt, order: .forward)
    ]) private var studentLessonsRaw: [StudentLesson]
    @Query private var studentsAll: [Student]

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
        lessonsVM.subjects(from: lessons)
    }

    // MARK: - Live computed caches from @Query
    private var lessonsByID: [UUID: Lesson] { vm.lessonsByID }

    private var studentLessonsByID: [UUID: StudentLesson] { vm.studentLessonsByID }

    private var nextLessonsForStudent: [StudentLessonSnapshot] { vm.nextLessonsForStudent }

    // Added filtered computed properties for student-specific data
    private var studentLessonsAll: [StudentLesson] { studentLessonsRaw.filter { $0.resolvedStudentIDs.contains(student.id) } }

    // Lightweight ID arrays to aid type-checker in onChange
    private var lessonIDs: [UUID] { lessons.map(\.id) }
    private var studentLessonIDs: [UUID] { studentLessonsAll.map(\.id) }

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
                    if let pid = row?.plannedItemID, let sl = studentLessonsRaw.first(where: { $0.id == pid }) {
                        vm.selectedStudentLessonForDetail = sl
                    } else {
                        let draft = createOrReuseNonGivenStudentLesson(for: lesson)
                        vm.selectedStudentLessonForDetail = draft
                        checklistVM.recompute(for: lessons, using: modelContext)
                    }
                },
                onTapPresented: { lesson, row in
                    if let presID = row?.presentationLogID, let sl = studentLessonsRaw.first(where: { $0.id == presID }) {
                        vm.selectedStudentLessonForDetail = sl
                    } else {
                        let sl = logPresentation(for: lesson)
                        _ = ensureContract(for: lesson, presentationStudentLesson: sl)
                    }
                },
                onTapActive: { lesson, row in
                    if let cid = row?.contractID, let c = fetchContract(by: cid) {
                        selectedContract = c
                    } else if (row?.isPresented ?? false) {
                        if let c = ensureContract(for: lesson, presentationStudentLesson: nil) {
                            selectedContract = c
                        }
                    }
                },
                onTapComplete: { lesson, row in
                    if let cid = row?.contractID, let c = fetchContract(by: cid), c.status != .complete {
                        c.status = .complete
                        c.completedAt = AppCalendar.startOfDay(Date())
                        _ = saveCoordinator.save(modelContext, reason: "Complete contract from checklist")
                        checklistVM.recompute(for: lessons, using: modelContext)
                    } else if (row?.isPresented ?? false) && row?.contractID == nil {
                        if let c = ensureContract(for: lesson, presentationStudentLesson: nil) {
                            c.status = .complete
                            c.completedAt = AppCalendar.startOfDay(Date())
                            _ = saveCoordinator.save(modelContext, reason: "Create-and-complete contract from checklist")
                            checklistVM.recompute(for: lessons, using: modelContext)
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

    // MARK: - Helper functions for contracts

    private func fetchContractsForStudent() -> [WorkContract] {
        let sid = student.id.uuidString
        let completeStatusRaw = WorkStatus.complete.rawValue

        let predicate = #Predicate<WorkContract> { contract in
            contract.studentID == sid && contract.statusRaw != completeStatusRaw
        }
        let descriptor = FetchDescriptor<WorkContract>(
            predicate: predicate,
            sortBy: [SortDescriptor(\WorkContract.createdAt, order: .reverse)]
        )
        let contracts = (try? modelContext.fetch(descriptor)) ?? []
        return contracts
    }

    private func createDraftStudentLesson(for lesson: Lesson) -> StudentLesson {
        // Reuse an existing unscheduled entry for this lesson+student if it exists
        if let existing = studentLessonsRaw.first(where: { $0.resolvedLessonID == lesson.id && $0.scheduledFor == nil && !$0.isGiven && Set($0.resolvedStudentIDs) == Set([student.id]) }) {
            return existing
        }

        let newSL = StudentLesson(
            id: UUID(),
            lessonID: lesson.id,
            studentIDs: [student.id],
            createdAt: Date(),
            scheduledFor: nil,
            givenAt: vm.giveStartGiven ? Date() : nil,
            isPresented: vm.giveStartGiven,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
        newSL.students = [student]
        // Removed line per instructions:
        // newSL.lesson = lesson
        modelContext.insert(newSL)
        _ = saveCoordinator.save(modelContext, reason: "Create draft student lesson")
        return newSL
    }

    private func createOrReuseNonGivenStudentLesson(for lesson: Lesson) -> StudentLesson {
        if let existing = studentLessonsRaw.first(where: { $0.resolvedLessonID == lesson.id && !$0.isGiven && Set($0.resolvedStudentIDs) == Set([student.id]) }) {
            return existing
        }
        let newSL = StudentLesson(
            id: UUID(),
            lessonID: lesson.id,
            studentIDs: [student.id],
            createdAt: Date(),
            scheduledFor: nil,
            givenAt: nil,
            isPresented: false,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
        newSL.students = [student]
        // Removed line per instructions:
        // newSL.lesson = lesson
        modelContext.insert(newSL)
        _ = saveCoordinator.save(modelContext, reason: "Create or reuse non-given student lesson")
        return newSL
    }

    private func logPresentation(for lesson: Lesson) -> StudentLesson {
        let newSL = StudentLesson(
            id: UUID(),
            lessonID: lesson.id,
            studentIDs: [student.id],
            createdAt: Date(),
            scheduledFor: nil,
            givenAt: nil,
            isPresented: true,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
        newSL.students = [student]
        // Removed line per instructions:
        // newSL.lesson = lesson
        modelContext.insert(newSL)
        _ = saveCoordinator.save(modelContext, reason: "Log presentation student lesson")
        return newSL
    }

    private func ensureContract(for lesson: Lesson, presentationStudentLesson: StudentLesson?) -> WorkContract? {
        let sid = student.id.uuidString
        let lid = lesson.id.uuidString
        let activeRaw = WorkStatus.active.rawValue
        let reviewRaw = WorkStatus.review.rawValue
        let predicate = #Predicate<WorkContract> { contract in
            contract.studentID == sid &&
            contract.lessonID == lid &&
            (contract.statusRaw == activeRaw || contract.statusRaw == reviewRaw)
        }
        let descriptor = FetchDescriptor<WorkContract>(predicate: predicate)
        if let existing = (try? modelContext.fetch(descriptor))?.first {
            return existing
        }
        let newContract = WorkContract(
            id: UUID(),
            createdAt: Date(),
            studentID: student.id.uuidString,
            lessonID: lesson.id.uuidString,
            presentationID: presentationStudentLesson?.id.uuidString,
            status: .active,
            scheduledDate: nil,
            completedAt: nil,
            legacyStudentLessonID: nil
        )
        modelContext.insert(newContract)
        _ = saveCoordinator.save(modelContext, reason: "Create new work contract")
        return newContract
    }

    private func fetchContract(by id: UUID) -> WorkContract? {
        let descriptor = FetchDescriptor<WorkContract>(predicate: #Predicate<WorkContract> { $0.id == id })
        return (try? modelContext.fetch(descriptor))?.first
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
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Spacer()
                    if isEditing {
                        Button("Cancel") {
                            isEditing = false
                        }
                        Button("Save") {
                            let fn = draftFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
                            let ln = draftLastName.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !fn.isEmpty, !ln.isEmpty else { return }
                            student.firstName = fn
                            student.lastName = ln
                            student.birthday = draftBirthday
                            student.level = draftLevel
                            student.dateStarted = draftStartDate
                            _ = saveCoordinator.save(modelContext, reason: "Edit student details")
                            isEditing = false
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(draftFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        if selectedTab != .checklist {
                            Button("Edit") {
                                draftFirstName = student.firstName
                                draftLastName = student.lastName
                                draftBirthday = student.birthday
                                draftLevel = student.level
                                draftStartDate = student.dateStarted ?? Date()
                                isEditing = true
                            }
                        }
                        Button("Delete", role: .destructive) {
                            showDeleteAlert = true
                        }
                        Button("Done") {
                            if let onDone { onDone() } else { dismiss() }
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(.bar)
            }
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
            // Create a draft StudentLesson for this student and selected lesson
            let newSL = createDraftStudentLesson(for: lesson)

            StudentLessonDetailView(studentLesson: newSL) {
                vm.selectedLessonForGive = nil
            }
            #if os(macOS)
            .frame(minWidth: 720, minHeight: 640)
            .presentationSizingFitted()
            #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
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
        .onAppear {
            WorkDataMaintenance.backfillParticipantsIfNeeded(using: modelContext)
            WorkDataMaintenance.migrateWorksToContractsIfNeeded(using: modelContext)
            vm.updateData(lessons: lessons, studentLessons: studentLessonsAll)
            checklistVM.recompute(for: lessons, using: modelContext)
            ensureChecklistSubjectSelection()
            contractsCache = fetchContractsForStudent()
            vm.updateContracts(contractsCache)
        }
        .onChange(of: lessonIDs) { _, _ in
            vm.updateData(lessons: lessons, studentLessons: studentLessonsAll)
            checklistVM.recompute(for: lessons, using: modelContext)
            ensureChecklistSubjectSelection()
            contractsCache = fetchContractsForStudent()
            vm.updateContracts(contractsCache)
        }
        .onChange(of: studentLessonIDs) { _, _ in
            vm.updateData(lessons: lessons, studentLessons: studentLessonsAll)
            checklistVM.recompute(for: lessons, using: modelContext)
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

