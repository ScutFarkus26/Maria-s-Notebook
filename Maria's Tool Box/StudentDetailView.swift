// StudentDetailView.swift
// A focused sheet for displaying a student's details and upcoming lessons

import SwiftUI
import SwiftData

struct StudentDetailView: View {
    let student: Student
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @StateObject private var vm: StudentDetailViewModel

    @State private var isEditing = false
    @State private var draftFirstName = ""
    @State private var draftLastName = ""
    @State private var draftBirthday = Date()
    @State private var draftLevel: Student.Level = .lower
    @State private var draftStartDate = Date()
    @State private var showDeleteAlert = false
    private enum StudentDetailTab { case overview, checklist, history, meetings, notes }
    @State private var selectedTab: StudentDetailTab = .overview

    @AppStorage("StudentDetailView.selectedChecklistSubject") private var selectedChecklistSubjectRaw: String = ""

    @Query private var lessons: [Lesson]
    @Query(sort: [
        SortDescriptor(\StudentLesson.scheduledFor, order: .forward),
        SortDescriptor(\StudentLesson.createdAt, order: .forward)
    ]) private var studentLessonsRaw: [StudentLesson]
    @Query(sort: [
        SortDescriptor(\WorkModel.createdAt, order: .reverse)
    ]) private var workModelsRaw: [WorkModel]

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

    private var worksForStudent: [WorkModel] { vm.worksForStudent }

    private var nextLessonsForStudent: [StudentLessonSnapshot] { vm.nextLessonsForStudent }

    // Added filtered computed properties for student-specific data
    private var studentLessonsAll: [StudentLesson] { studentLessonsRaw.filter { $0.studentIDs.contains(student.id) } }
    private var workModelsAll: [WorkModel] { workModelsRaw.filter { $0.studentIDs.contains(student.id) } }

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
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: student.birthday, to: Date())
        let years = comps.year ?? 0
        if years <= 0 { return "Less than 1 year old" }
        if years == 1 { return "1 year old" }
        return "\(years) years old"
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

    private func latestStudentLesson(for lessonID: UUID, studentID: UUID) -> StudentLesson? {
        let matches = studentLessonsAll.filter { $0.lessonID == lessonID && $0.studentIDs.contains(studentID) }
        return matches.sorted { lhs, rhs in
            let lDate = lhs.givenAt ?? lhs.scheduledFor ?? lhs.createdAt
            let rDate = rhs.givenAt ?? rhs.scheduledFor ?? rhs.createdAt
            return lDate > rDate
        }.first
    }

    private func upcomingStudentLesson(for lessonID: UUID, studentID: UUID) -> StudentLesson? {
        let matches = studentLessonsAll.filter { $0.lessonID == lessonID && $0.studentIDs.contains(studentID) && !$0.isGiven }
        return matches.sorted { lhs, rhs in
            switch (lhs.scheduledFor, rhs.scheduledFor) {
            case let (l?, r?):
                return l < r
            case (nil, nil):
                return lhs.createdAt < rhs.createdAt
            case (nil, _?):
                return false
            case (_?, nil):
                return true
            }
        }.first
    }

    private var practiceLessonIDs: Set<UUID> { vm.workSummary.practiceLessonIDs }

    private var followUpLessonIDs: Set<UUID> { vm.workSummary.followUpLessonIDs }

    private var pendingPracticeLessonIDs: Set<UUID> { vm.workSummary.pendingPracticeLessonIDs }

    private var pendingFollowUpLessonIDs: Set<UUID> { vm.workSummary.pendingFollowUpLessonIDs }

    private var pendingWorkLessonIDs: Set<UUID> { vm.workSummary.pendingWorkLessonIDs }

    private var masteredLessonIDs: Set<UUID> { vm.masteredLessonIDs }

    private func workLinkedStudentLesson(for work: WorkModel) -> StudentLesson? {
        guard let slID = work.studentLessonID else { return nil }
        return studentLessonsByID[slID]
    }

    private func workLesson(for work: WorkModel) -> Lesson? {
        guard let sl = workLinkedStudentLesson(for: work) else { return nil }
        return lessonsByID[sl.lessonID]
    }

    private func workTitle(for work: WorkModel) -> String {
        let t = work.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        if let lesson = workLesson(for: work) { return lesson.name }
        return work.workType.rawValue
    }

    private func workSubtitle(for work: WorkModel) -> String? {
        let date: Date = {
            if let sl = workLinkedStudentLesson(for: work) {
                return sl.givenAt ?? sl.scheduledFor ?? sl.createdAt
            }
            return work.createdAt
        }()
        let dateString = DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        if let lesson = workLesson(for: work) {
            let subject = lesson.subject
            let type = work.workType.rawValue
            let base = subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? type : "\(type) • \(subject)"
            return "\(base) • \(dateString)"
        }
        return dateString
    }

    private func iconAndColor(for type: WorkModel.WorkType) -> (String, Color) {
        switch type {
        case .research: return ("magnifyingglass", .teal)
        case .followUp: return ("bolt.fill", .orange)
        case .practice: return ("arrow.triangle.2.circlepath", .purple)
        }
    }

    /*
    private var headerContent: some View {
        // Replaced by StudentHeaderView
    }
    */

    // Helper function renamed to avoid conflict with @Query var lessons
    private func lessonsIn(group: String, subject: String) -> [Lesson] {
        return lessons.filter { lesson in
            lesson.subject.caseInsensitiveCompare(subject) == .orderedSame && lesson.group.caseInsensitiveCompare(group) == .orderedSame
        }
    }

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
            HStack {
                Spacer()
                HStack(spacing: 12) {
                    PillNavButton(title: "Overview", isSelected: selectedTab == .overview) { selectedTab = .overview }
                    PillNavButton(title: "Checklist", isSelected: selectedTab == .checklist) { selectedTab = .checklist }
                    PillNavButton(title: "History", isSelected: selectedTab == .history) { selectedTab = .history }
                    PillNavButton(title: "Meetings", isSelected: selectedTab == .meetings) { selectedTab = .meetings }
                    PillNavButton(title: "Notes", isSelected: selectedTab == .notes) { selectedTab = .notes }
                }
                Spacer()
            }
            .padding(.top, 8)
            .padding(.bottom, 8)

            Divider()
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 28) {
                    if selectedTab == .overview {
                        StudentDetailHeaderView(student: student)
                            .padding(.top, 36)

                        if isEditing {
                            editForm
                        } else {
                            infoRows

                            Divider()
                                .padding(.top, 8)

                            WorkListSection(works: worksForStudent, workTitle: workTitle(for:), workSubtitle: workSubtitle(for:), iconAndColor: iconAndColor(for:))

                            Divider()
                                .padding(.top, 8)

                            NextLessonsSection(snapshots: nextLessonsForStudent, lessonsByID: lessonsByID)
                        }
                    } else if selectedTab == .checklist {
                        VStack(alignment: .leading, spacing: 16) {
                            SubjectPillsView(subjects: subjectsForChecklist, selected: selectedChecklistSubject) { subject in
                                setSelectedChecklistSubject(subject)
                            }

                            if let subject = selectedChecklistSubject ?? subjectsForChecklist.first {
                                SubjectChecklistSection(
                                    subject: subject,
                                    orderedGroups: lessonsVM.groups(for: subject, lessons: lessons),
                                    lessons: lessons,
                                    masteredLessonIDs: masteredLessonIDs,
                                    pendingWorkLessonIDs: pendingWorkLessonIDs,
                                    plannedLessonIDs: plannedLessonIDs,
                                    practiceLessonIDs: practiceLessonIDs,
                                    pendingPracticeLessonIDs: pendingPracticeLessonIDs,
                                    followUpLessonIDs: followUpLessonIDs,
                                    pendingFollowUpLessonIDs: pendingFollowUpLessonIDs,
                                    onTogglePresented: { vm.togglePresented(for: $0, modelContext: modelContext) },
                                    onOpenMastered: { vm.openMastered(for: $0, modelContext: modelContext) },
                                    onOpenPlan: { vm.openPlan(for: $0, modelContext: modelContext) },
                                    onTogglePractice: { vm.toggleWork(for: $0, type: .practice, modelContext: modelContext) },
                                    onOpenPractice: { vm.openWork(for: $0, type: .practice, modelContext: modelContext) },
                                    onToggleFollowUp: { vm.toggleWork(for: $0, type: .followUp, modelContext: modelContext) },
                                    onOpenFollowUp: { vm.openWork(for: $0, type: .followUp, modelContext: modelContext) }
                                )
                            } else {
                                ContentUnavailableView(
                                    "No Subjects",
                                    systemImage: "text.book.closed",
                                    description: Text("Add lessons in Albums to see subjects here.")
                                )
                                .frame(maxWidth: .infinity, alignment: .center)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 36)
                    } else if selectedTab == .history {
                        historyPlaceholder
                            .padding(.top, 36)
                    } else if selectedTab == .meetings {
                        meetingsPlaceholder
                            .padding(.top, 36)
                    } else if selectedTab == .notes {
                        notesPlaceholder
                            .padding(.top, 36)
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
#if os(macOS)
        .frame(minWidth: 860, minHeight: 640)
        .presentationSizing(.fitted)
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
                            try? modelContext.save()
                            isEditing = false
                        }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(draftFirstName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draftLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } else {
                        Button("Edit") {
                            draftFirstName = student.firstName
                            draftLastName = student.lastName
                            draftBirthday = student.birthday
                            draftLevel = student.level
                            draftStartDate = student.dateStarted ?? Date()
                            isEditing = true
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
                if let onDone { onDone() } else { dismiss() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
        .sheet(item: $vm.selectedLessonForGive) { l in
            GiveLessonSheet(lesson: l, preselectedStudentIDs: [student.id], startGiven: vm.giveStartGiven) {
                vm.selectedLessonForGive = nil
            }
            #if os(macOS)
            .frame(minWidth: 720, minHeight: 640)
            .presentationSizing(.fitted)
            #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .sheet(item: $vm.selectedWorkForDetail) { w in
            WorkDetailView(work: w) {
                vm.selectedWorkForDetail = nil
            }
            #if os(macOS)
            .frame(minWidth: 720, minHeight: 640)
            .presentationSizing(.fitted)
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
            .presentationSizing(.fitted)
            #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .onAppear {
            vm.updateData(lessons: lessons, studentLessons: studentLessonsAll, workModels: workModelsAll)
            ensureChecklistSubjectSelection()
        }
        .onChange(of: lessons.map { $0.id }) { _ in
            vm.updateData(lessons: lessons, studentLessons: studentLessonsAll, workModels: workModelsAll)
            ensureChecklistSubjectSelection()
        }
        .onChange(of: studentLessonsAll.map { $0.id }) { _ in
            vm.updateData(lessons: lessons, studentLessons: studentLessonsAll, workModels: workModelsAll)
        }
        .onChange(of: workModelsAll.map { $0.id }) { _ in
            vm.updateData(lessons: lessons, studentLessons: studentLessonsAll, workModels: workModelsAll)
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

    init(student: Student, onDone: (() -> Void)? = nil) {
        self.student = student
        self.onDone = onDone
        _vm = StateObject(wrappedValue: StudentDetailViewModel(student: student))
    }

    // MARK: - Reintroduced helpers (Phase 5 safety)

    private var infoRows: some View {
        VStack(spacing: 14) {
            InfoRowView(icon: "calendar", title: "Birthday", value: formattedBirthday)
            if let ds = student.dateStarted {
                InfoRowView(icon: "calendar.badge.clock", title: "Start Date", value: Self.birthdayFormatter.string(from: ds))
            }
            InfoRowView(icon: "gift", title: "Age", value: ageDescription)
            InfoRowView(icon: "graduationcap", title: "Florida Grade Equivalent", value: FloridaGradeCalculator.grade(for: student.birthday).displayString)
        }
        .padding(.horizontal, 8)
    }

    private var editForm: some View {
        VStack(spacing: 14) {
            HStack {
                TextField("First Name", text: $draftFirstName)
                    .textFieldStyle(.roundedBorder)
                TextField("Last Name", text: $draftLastName)
                    .textFieldStyle(.roundedBorder)
            }
            DatePicker("Birthday", selection: $draftBirthday, displayedComponents: .date)
            DatePicker("Start Date", selection: $draftStartDate, displayedComponents: .date)
            Picker("Level", selection: $draftLevel) {
                Text(Student.Level.lower.rawValue).tag(Student.Level.lower)
                Text(Student.Level.upper.rawValue).tag(Student.Level.upper)
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 8)
    }

    private var historyPlaceholder: some View {
        ContentUnavailableView(
            "History",
            systemImage: "clock.arrow.circlepath",
            description: Text("This will show the student's history.")
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var meetingsPlaceholder: some View {
        ContentUnavailableView(
            "Meetings",
            systemImage: "person.2",
            description: Text("This will show the student's meetings.")
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var notesPlaceholder: some View {
        ContentUnavailableView(
            "Notes",
            systemImage: "note.text",
            description: Text("This will show the student's notes.")
        )
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private static let birthdayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .none
        return df
    }()
}
#Preview {
    // NOTE: This preview uses placeholders and will need a real Student from your model to render accurately.
    // Creating a lightweight mock to preview layout only.
    struct MockStudent: Hashable {
        var fullName: String
        var birthday: Date
        enum Level: String { case upper = "Upper", lower = "Lower" }
        var level: Level
        var nextLessons: [Int]
    }
    // The preview below is a visual placeholder and not compiled with the app target.
    return Text("StudentDetailView Preview requires app data model.")
}

