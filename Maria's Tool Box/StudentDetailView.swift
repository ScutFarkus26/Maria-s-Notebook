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
    @Query private var studentLessonsAll: [StudentLesson]
    @Query private var workModelsAll: [WorkModel]

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
        if let lesson = workLesson(for: work) { return lesson.name }
        return work.workType.rawValue
    }

    private func workSubtitle(for work: WorkModel) -> String? {
        if let lesson = workLesson(for: work) {
            let subject = lesson.subject
            let type = work.workType.rawValue
            if subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return type }
            return "\(type) • \(subject)"
        }
        return nil
    }

    private func iconAndColor(for type: WorkModel.WorkType) -> (String, Color) {
        switch type {
        case .research: return ("magnifyingglass", .teal)
        case .followUp: return ("bolt.fill", .orange)
        case .practice: return ("arrow.triangle.2.circlepath", .purple)
        }
    }

    private var nextLessonsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Next Lessons")
                    .font(.system(size: AppTheme.FontSize.header, weight: .heavy, design: .rounded))
                Spacer()
                Text("\(nextLessonsForStudent.count)")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            if nextLessonsForStudent.isEmpty {
                Text("No lessons scheduled yet.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            } else {
                VStack(spacing: 10) {
                    ForEach(nextLessonsForStudent, id: \.id) { sl in
                        HStack(spacing: 12) {
                            Image(systemName: "book")
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundStyle(.blue)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(lessonName(for: sl))
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                if let subject = lessonSubject(for: sl), !subject.isEmpty {
                                    Text(subject)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private var workingOnSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Working on")
                    .font(.system(size: AppTheme.FontSize.header, weight: .heavy, design: .rounded))
                Spacer()
                Text("\(worksForStudent.count)")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            if worksForStudent.isEmpty {
                Text("No work recorded yet.")
                    .foregroundStyle(.secondary)
                    .padding(.top, 6)
            } else {
                VStack(spacing: 10) {
                    ForEach(worksForStudent, id: \.id) { work in
                        HStack(spacing: 12) {
                            let pair = iconAndColor(for: work.workType)
                            Image(systemName: pair.0)
                                .font(.system(size: 20, weight: .semibold, design: .rounded))
                                .foregroundStyle(pair.1)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(workTitle(for: work))
                                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                                if let subtitle = workSubtitle(for: work), !subtitle.isEmpty {
                                    Text(subtitle)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            Spacer()
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
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

    // MARK: - Overview helpers and placeholders

    private var headerContent: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            gradient: Gradient(colors: [Color.purple, Color.pink]),
                            center: .center,
                            startRadius: 8,
                            endRadius: 72
                        )
                    )
                    .frame(width: 120, height: 120)
                    .shadow(color: Color.pink.opacity(0.25), radius: 24, x: 0, y: 10)

                Text(initials)
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text(student.fullName)
                .font(.system(size: AppTheme.FontSize.titleXLarge, weight: .black, design: .rounded))

            Text(student.level.rawValue)
                .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(levelColor.opacity(0.12)))
        }
        .frame(maxWidth: .infinity)
    }

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

    private func lessonName(for sl: StudentLessonSnapshot) -> String {
        return lessonsByID[sl.lessonID]?.name ?? "Lesson"
    }

    private func lessonSubject(for sl: StudentLessonSnapshot) -> String? {
        return lessonsByID[sl.lessonID]?.subject
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

    private var checklistPlaceholder: some View {
        VStack(alignment: .leading, spacing: 16) {
            subjectPills

            if let subject = selectedChecklistSubject ?? subjectsForChecklist.first {
                subjectChecklist(subject)
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
    }

    private var subjectPills: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(subjectsForChecklist, id: \.self) { subject in
                    let isSelected = selectedChecklistSubject?.caseInsensitiveCompare(subject) == .orderedSame
                    Button {
                        setSelectedChecklistSubject(subject)
                    } label: {
                        Text(subject)
                            .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                Capsule().fill(isSelected ? AppColors.color(forSubject: subject) : Color.platformBackground)
                            )
                            .foregroundStyle(isSelected ? Color.white : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func subjectChecklist(_ subject: String) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(subject) Checklist")
                    .font(.system(size: AppTheme.FontSize.header, weight: .heavy, design: .rounded))
                Spacer()
            }
            .padding(.top, 4)

            let orderedGroups = lessonsVM.groups(for: subject, lessons: lessons)
            if orderedGroups.isEmpty {
                ContentUnavailableView(
                    "No \(subject) Lessons",
                    systemImage: "text.book.closed",
                    description: Text("Add lessons in Albums to see them here.")
                )
                .frame(maxWidth: .infinity, alignment: .center)
            } else {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(orderedGroups, id: \.self) { group in
                        let items = lessonsIn(group: group, subject: subject)
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Image(systemName: "tag.fill")
                                        .foregroundStyle(AppColors.color(forSubject: subject))
                                    Text(group)
                                        .font(.system(size: AppTheme.FontSize.titleSmall, weight: .semibold, design: .rounded))
                                }
                                VStack(spacing: 8) {
                                    ForEach(items, id: \.id) { lesson in
                                        let wasPresented = masteredLessonIDs.contains(lesson.id)
                                        let hasPending = pendingWorkLessonIDs.contains(lesson.id)
                                        let isPlanned = plannedLessonIDs.contains(lesson.id)

                                        HStack(spacing: 12) {
                                            // Lifecycle indicator token
                                            LifecycleIndicatorView(wasPresented: wasPresented, hasPending: hasPending, isPlanned: isPlanned)
                                                .frame(width: 22, height: 22)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(lesson.name)
                                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                                if !lesson.subheading.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                                    Text(lesson.subheading)
                                                        .font(.system(size: 13, weight: .regular, design: .rounded))
                                                        .foregroundStyle(.secondary)
                                                }
                                            }

                                            Spacer(minLength: 0)

                                            HStack(spacing: 10) {
                                                // Presented toggle
                                                Button { vm.togglePresented(for: lesson, modelContext: modelContext) } label: {
                                                    ZStack {
                                                        if !wasPresented && isPlanned {
                                                            Circle()
                                                                .stroke(Color.green, lineWidth: 1)
                                                        }
                                                        Image(systemName: "checkmark")
                                                            .foregroundStyle(wasPresented ? Color.green : Color.secondary)
                                                    }
                                                    .frame(width: 22, height: 22)
                                                }
                                                .buttonStyle(.plain)
                                                .contextMenu {
                                                    Button("Open Presentation Details…") { vm.openMastered(for: lesson, modelContext: modelContext) }
                                                    Button("Plan Presentation…") { vm.openPlan(for: lesson, modelContext: modelContext) }
                                                }
                                                .help(isPlanned ? "Planned — tap to mark presented or open details" : (wasPresented ? "Presented — tap to review or unmark" : "Mark as presented"))

                                                // Practice work toggle
                                                Button { vm.toggleWork(for: lesson, type: .practice, modelContext: modelContext) } label: {
                                                    let hasPractice = practiceLessonIDs.contains(lesson.id)
                                                    let isPendingPractice = pendingPracticeLessonIDs.contains(lesson.id)
                                                    ZStack {
                                                        if hasPractice && isPendingPractice {
                                                            Circle()
                                                                .stroke(Color.purple, lineWidth: 2)
                                                                .frame(width: 18, height: 18)
                                                        }
                                                        Image(systemName: "arrow.triangle.2.circlepath")
                                                            .foregroundStyle(hasPractice && !isPendingPractice ? Color.purple : Color.secondary)
                                                    }
                                                    .frame(width: 22, height: 22)
                                                }
                                                .buttonStyle(.plain)
                                                .contextMenu {
                                                    Button("Open Practice Work…") { vm.openWork(for: lesson, type: .practice, modelContext: modelContext) }
                                                }
                                                .help(!practiceLessonIDs.contains(lesson.id) ? "Add practice work" : (pendingPracticeLessonIDs.contains(lesson.id) ? "Practice pending — tap to mark complete or open work" : "Practice completed — tap to toggle or open work"))

                                                // Follow-up work toggle
                                                Button { vm.toggleWork(for: lesson, type: .followUp, modelContext: modelContext) } label: {
                                                    let hasFollowUp = followUpLessonIDs.contains(lesson.id)
                                                    let isPendingFollowUp = pendingFollowUpLessonIDs.contains(lesson.id)
                                                    ZStack {
                                                        if hasFollowUp && isPendingFollowUp {
                                                            Circle()
                                                                .stroke(Color.orange, lineWidth: 2)
                                                                .frame(width: 18, height: 18)
                                                        }
                                                        Image(systemName: "bolt.fill")
                                                            .foregroundStyle(hasFollowUp && !isPendingFollowUp ? Color.orange : Color.secondary)
                                                    }
                                                    .frame(width: 22, height: 22)
                                                }
                                                .buttonStyle(.plain)
                                                .contextMenu {
                                                    Button("Open Follow Up Work…") { vm.openWork(for: lesson, type: .followUp, modelContext: modelContext) }
                                                }
                                                .help(!followUpLessonIDs.contains(lesson.id) ? "Add follow-up work" : (pendingFollowUpLessonIDs.contains(lesson.id) ? "Follow-up pending — tap to mark complete or open work" : "Follow-up completed — tap to toggle or open work"))
                                            }
                                            .frame(minWidth: 0)
                                        }
                                        .padding(.vertical, 6)
                                    }
                                }
                                .padding(.leading, 4)
                            }
                        }
                    }
                }
            }
        }
    }

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
                        headerContent
                            .padding(.top, 36)

                        if isEditing {
                            editForm
                        } else {
                            infoRows

                            Divider()
                                .padding(.top, 8)

                            workingOnSection

                            Divider()
                                .padding(.top, 8)

                            nextLessonsSection
                        }
                    } else if selectedTab == .checklist {
                        checklistPlaceholder
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
            bottomBar
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

        let sid = student.id
        _studentLessonsAll = Query(
            filter: #Predicate<StudentLesson> { $0.studentIDs.contains(sid) },
            sort: [
                SortDescriptor(\.scheduledFor, order: .forward),
                SortDescriptor(\.createdAt, order: .forward)
            ]
        )
        _workModelsAll = Query(
            filter: #Predicate<WorkModel> { $0.studentIDs.contains(sid) },
            sort: [
                SortDescriptor(\.createdAt, order: .reverse)
            ]
        )
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
