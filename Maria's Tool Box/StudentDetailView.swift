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
    private var studentLessonsAll: [StudentLesson] { studentLessonsRaw.filter { $0.resolvedStudentIDs.contains(student.id) } }
    private var workModelsAll: [WorkModel] { workModelsRaw.filter { $0.resolvedStudentIDs.contains(student.id) } }

    // Lightweight ID arrays to aid type-checker in onChange
    private var lessonIDs: [UUID] { lessons.map(\.id) }
    private var studentLessonIDs: [UUID] { studentLessonsAll.map(\.id) }
    private var workModelIDs: [UUID] { workModelsAll.map(\.id) }

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

    private var attendanceSummaryThisSchoolYear: String {
        let tardy = daysTardyThisSchoolYear
        let absent = daysAbsentThisSchoolYear
        return "Days Tardy: \(tardy) • Days Absent: \(absent)"
    }

    private var daysTardyThisSchoolYear: Int {
        let calendar = Calendar.current
        let start = FloridaGradeCalculator.schoolYearStart(for: Date(), calendar: calendar)
        guard let end = calendar.date(byAdding: .year, value: 1, to: start) else { return 0 }
        let studentID = student.id
        let from = start
        let to = end
        let descriptor = FetchDescriptor<AttendanceRecord>(
            predicate: #Predicate<AttendanceRecord> { rec in
                rec.studentID == studentID && rec.date >= from && rec.date < to
            }
        )
        let records = (try? modelContext.fetch(descriptor)) ?? []
        return records.filter { $0.status == .tardy }.count
    }

    private var daysAbsentThisSchoolYear: Int {
        let calendar = Calendar.current
        let start = FloridaGradeCalculator.schoolYearStart(for: Date(), calendar: calendar)
        guard let end = calendar.date(byAdding: .year, value: 1, to: start) else { return 0 }
        let studentID = student.id
        let from = start
        let to = end
        let descriptor = FetchDescriptor<AttendanceRecord>(
            predicate: #Predicate<AttendanceRecord> { rec in
                rec.studentID == studentID && rec.date >= from && rec.date < to
            }
        )
        let records = (try? modelContext.fetch(descriptor)) ?? []
        return records.filter { $0.status == .absent }.count
    }

    private func metricBadge(label: String, count: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
            Text("\(count)")
                .font(.system(size: AppTheme.FontSize.captionSmall, weight: .semibold, design: .rounded))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(color.opacity(0.15))
        )
        .foregroundStyle(color)
    }

    private var attendanceInfoRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "calendar.badge.checkmark")
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                Text("Attendance (This School Year)")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            HStack(spacing: 8) {
                metricBadge(label: "Tardy", count: daysTardyThisSchoolYear, color: .blue)
                metricBadge(label: "Absent", count: daysAbsentThisSchoolYear, color: .red)
            }
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
                                makeChecklistSection(for: subject)
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
        .sheet(item: $vm.selectedLessonForGive) { lesson in
            // Create a draft StudentLesson for this student and selected lesson
            let newSL = createDraftStudentLesson(for: lesson)

            StudentLessonDetailView(studentLesson: newSL) {
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
            WorkDetailContainerView(workID: w.id) {
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
            WorkDataMaintenance.backfillParticipantsIfNeeded(using: modelContext)
            vm.updateData(lessons: lessons, studentLessons: studentLessonsAll, workModels: workModelsAll)
            ensureChecklistSubjectSelection()
        }
        .onChange(of: lessonIDs) { _, _ in
            vm.updateData(lessons: lessons, studentLessons: studentLessonsAll, workModels: workModelsAll)
            ensureChecklistSubjectSelection()
        }
        .onChange(of: studentLessonIDs) { _, _ in
            vm.updateData(lessons: lessons, studentLessons: studentLessonsAll, workModels: workModelsAll)
        }
        .onChange(of: workModelIDs) { _, _ in
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
            attendanceInfoRow
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

    // MARK: - Extracted builders to help the type-checker
    private func makeChecklistSection(for subject: String) -> some View {
        let groups = lessonsVM.groups(for: subject, lessons: lessons)
        return SubjectChecklistSection(
            subject: subject,
            orderedGroups: groups,
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
        newSL.lesson = lesson
        modelContext.insert(newSL)
        try? modelContext.save()
        return newSL
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

