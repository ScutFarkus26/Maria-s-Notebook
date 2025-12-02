// StudentDetailView.swift
// A focused sheet for displaying a student's details and upcoming lessons

import SwiftUI
import SwiftData

struct StudentDetailView: View {
    let student: Student
    var onDone: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var isEditing = false
    @State private var draftFirstName = ""
    @State private var draftLastName = ""
    @State private var draftBirthday = Date()
    @State private var draftLevel: Student.Level = .lower
    @State private var draftStartDate = Date()
    @State private var showDeleteAlert = false
    @State private var showPlannedBanner: Bool = false
    private enum Tab { case overview, checklist, history, meetings, notes }
    @State private var selectedTab: Tab = .overview

    @State private var nextLessonsForStudent: [StudentLessonSnapshot] = []
    @State private var lessonsByID: [UUID: Lesson] = [:]
    @State private var isLoadingLessons = true

    @State private var worksForStudent: [WorkModel] = []
    @State private var studentLessonsByID: [UUID: StudentLesson] = [:]
    @State private var isLoadingWorks = true

    @State private var showingGiveLessonSheet: Bool = false
    @State private var selectedLessonForGive: Lesson? = nil
    @State private var giveStartGiven: Bool = false

    @State private var showingWorkDetailSheet: Bool = false
    @State private var selectedWorkForDetail: WorkModel? = nil

    @State private var showingStudentLessonDetailSheet: Bool = false
    @State private var selectedStudentLessonForDetail: StudentLesson? = nil

    @AppStorage("StudentDetailView.selectedChecklistSubject") private var selectedChecklistSubjectRaw: String = ""

    @Query private var lessons: [Lesson]
    @Query private var studentLessonsAll: [StudentLesson]

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

    private var plannedLessonIDs: Set<UUID> {
        Set(nextLessonsForStudent.map { $0.lessonID })
    }

    private func latestStudentLesson(for lessonID: UUID, studentID: UUID) -> StudentLesson? {
        let matches = studentLessonsAll.filter { $0.lessonID == lessonID && $0.studentIDs.contains(studentID) }
        return matches.sorted { lhs, rhs in
            let lDate = lhs.givenAt ?? lhs.scheduledFor ?? lhs.createdAt
            let rDate = rhs.givenAt ?? rhs.scheduledFor ?? rhs.createdAt
            return lDate > rDate
        }.first
    }

    private func upcomingStudentLesson(for lessonID: UUID, studentID: UUID) -> StudentLesson? {
        let matches = studentLessonsAll.filter { $0.lessonID == lessonID && $0.studentIDs.contains(studentID) && $0.givenAt == nil }
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

    private func openPlan(for lesson: Lesson) {
        if let sl = upcomingStudentLesson(for: lesson.id, studentID: student.id) {
            selectedStudentLessonForDetail = sl
            showingStudentLessonDetailSheet = true
        } else {
            selectedLessonForGive = lesson
            giveStartGiven = false
            showingGiveLessonSheet = true
        }
    }

    private func openMastered(for lesson: Lesson) {
        // If there is a given student lesson, open it; otherwise start the Give flow in Given mode
        if let sl = studentLessonsAll.filter({ $0.lessonID == lesson.id && $0.studentIDs.contains(student.id) && $0.givenAt != nil }).sorted(by: { ($0.givenAt ?? $0.createdAt) > ($1.givenAt ?? $1.createdAt) }).first {
            selectedStudentLessonForDetail = sl
            showingStudentLessonDetailSheet = true
        } else {
            selectedLessonForGive = lesson
            giveStartGiven = true
            showingGiveLessonSheet = true
        }
    }

    private func openWork(for lesson: Lesson, type: WorkModel.WorkType) {
        if let existing = worksForStudent.first(where: { work in
            work.workType == type && (workLesson(for: work)?.id == lesson.id)
        }) {
            selectedWorkForDetail = existing
            showingWorkDetailSheet = true
            return
        }
        // Create a new WorkModel linked to the most relevant StudentLesson if possible
        let sl = latestStudentLesson(for: lesson.id, studentID: student.id) ?? {
            let created = StudentLesson(
                lessonID: lesson.id,
                studentIDs: [student.id],
                createdAt: Date(),
                scheduledFor: nil,
                givenAt: nil,
                notes: "",
                needsPractice: false,
                needsAnotherPresentation: false,
                followUpWork: ""
            )
            modelContext.insert(created)
            try? modelContext.save()
            return created
        }()
        let work = WorkModel(
            id: UUID(),
            studentIDs: [student.id],
            workType: type,
            studentLessonID: sl.id,
            notes: "",
            createdAt: Date()
        )
        work.ensureParticipantsFromStudentIDs()
        modelContext.insert(work)
        try? modelContext.save()
        selectedWorkForDetail = work
        showingWorkDetailSheet = true
    }

    private func groupsOrdered(for subject: String) -> [String] {
        lessonsVM.groups(for: subject, lessons: lessons)
    }

    private func lessons(in group: String, subject: String) -> [Lesson] {
        let sub = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let groupTrimmed = group.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = lessons.filter { l in
            l.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(sub) == .orderedSame &&
            l.group.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(groupTrimmed) == .orderedSame
        }
        return filtered.sorted { lhs, rhs in
            if lhs.orderInGroup == rhs.orderInGroup {
                let nameOrder = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
                if nameOrder == .orderedSame { return lhs.id.uuidString < rhs.id.uuidString }
                return nameOrder == .orderedAscending
            }
            return lhs.orderInGroup < rhs.orderInGroup
        }
    }

    private var practiceLessonIDs: Set<UUID> {
        let ids: [UUID] = worksForStudent.filter { $0.workType == .practice }.compactMap { work in
            return workLesson(for: work)?.id
        }
        return Set(ids)
    }

    private var followUpLessonIDs: Set<UUID> {
        let ids: [UUID] = worksForStudent.filter { $0.workType == .followUp }.compactMap { work in
            return workLesson(for: work)?.id
        }
        return Set(ids)
    }

    private var pendingPracticeLessonIDs: Set<UUID> {
        let sid = student.id
        let ids: [UUID] = worksForStudent.filter { work in
            work.workType == .practice && !work.isStudentCompleted(sid)
        }.compactMap { work in
            return workLesson(for: work)?.id
        }
        return Set(ids)
    }

    private var pendingFollowUpLessonIDs: Set<UUID> {
        let sid = student.id
        let ids: [UUID] = worksForStudent.filter { work in
            work.workType == .followUp && !work.isStudentCompleted(sid)
        }.compactMap { work in
            return workLesson(for: work)?.id
        }
        return Set(ids)
    }

    private var pendingWorkLessonIDs: Set<UUID> {
        let sid = student.id
        let ids: [UUID] = worksForStudent.filter { work in
            (work.workType == .practice || work.workType == .followUp) && !work.isStudentCompleted(sid)
        }.compactMap { work in
            return workLesson(for: work)?.id
        }
        return Set(ids)
    }

    private var masteredLessonIDs: Set<UUID> {
        let ids: [UUID] = studentLessonsAll.filter { sl in
            sl.givenAt != nil && sl.studentIDs.contains(student.id)
        }.map { $0.lessonID }
        return Set(ids)
    }

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
                let total = lessons.filter { $0.subject.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(subject) == .orderedSame }.count
                Text("\(total)")
                    .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 4)

            let orderedGroups = groupsOrdered(for: subject)
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
                        let items = lessons(in: group, subject: subject)
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
                                        HStack(spacing: 12) {
                                            let wasPresented = masteredLessonIDs.contains(lesson.id)
                                            let hasPending = pendingWorkLessonIDs.contains(lesson.id)
                                            Image(systemName: wasPresented ? (hasPending ? "circle" : "circle.fill") : "circle")
                                                .foregroundStyle(wasPresented ? Color.accentColor : Color.secondary)
                                                .frame(width: 22)
                                                .help(wasPresented ? (hasPending ? "Presented • pending practice/follow-up" : "Presented • no pending work") : "Not presented yet")

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
                                                Button { openMastered(for: lesson) } label: {
                                                    let isMastered = masteredLessonIDs.contains(lesson.id)
                                                    let isPlanned = plannedLessonIDs.contains(lesson.id)
                                                    ZStack {
                                                        if isPlanned {
                                                            Circle()
                                                                .stroke(Color.green.opacity(0.35), lineWidth: 1)
                                                                .frame(width: 22, height: 22)
                                                        }
                                                        Image(systemName: "checkmark.seal.fill")
                                                            .foregroundStyle(isMastered ? Color.green : Color.secondary)
                                                            .accessibilityLabel("Mastered")
                                                    }
                                                    .frame(width: 22, height: 22)
                                                }
                                                .buttonStyle(.plain)
                                                .help(masteredLessonIDs.contains(lesson.id) ? "View presentation details" : (plannedLessonIDs.contains(lesson.id) ? "Planned — open presentation" : "Mark as given"))

                                                Button { openWork(for: lesson, type: .practice) } label: {
                                                    let hasPractice = practiceLessonIDs.contains(lesson.id)
                                                    let isPendingPractice = pendingPracticeLessonIDs.contains(lesson.id)
                                                    ZStack {
                                                        if hasPractice && isPendingPractice {
                                                            Circle()
                                                                .stroke(Color.purple.opacity(0.35), lineWidth: 1)
                                                                .frame(width: 22, height: 22)
                                                        }
                                                        Image(systemName: "arrow.triangle.2.circlepath")
                                                            .foregroundStyle(hasPractice ? Color.purple : Color.secondary)
                                                    }
                                                    .frame(width: 22, height: 22)
                                                    .accessibilityLabel(!hasPractice ? "Practice" : (isPendingPractice ? "Practice pending" : "Practice completed"))
                                                }
                                                .buttonStyle(.plain)
                                                .help(!practiceLessonIDs.contains(lesson.id) ? "Add practice work" : (pendingPracticeLessonIDs.contains(lesson.id) ? "Practice pending — view work" : "Practice completed — view work"))

                                                Button { openWork(for: lesson, type: .followUp) } label: {
                                                    let hasFollowUp = followUpLessonIDs.contains(lesson.id)
                                                    let isPendingFollowUp = pendingFollowUpLessonIDs.contains(lesson.id)
                                                    ZStack {
                                                        if hasFollowUp && isPendingFollowUp {
                                                            Circle()
                                                                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                                                                .frame(width: 22, height: 22)
                                                        }
                                                        Image(systemName: "bolt.fill")
                                                            .foregroundStyle(hasFollowUp ? Color.orange : Color.secondary)
                                                    }
                                                    .frame(width: 22, height: 22)
                                                    .accessibilityLabel(!hasFollowUp ? "Follow-up" : (isPendingFollowUp ? "Follow-up pending" : "Follow-up completed"))
                                                }
                                                .buttonStyle(.plain)
                                                .help(!followUpLessonIDs.contains(lesson.id) ? "Add follow-up work" : (pendingFollowUpLessonIDs.contains(lesson.id) ? "Follow-up pending — view work" : "Follow-up completed — view work"))
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

            Divider()
                .padding(.top, 8)

            ScrollView {
                VStack(spacing: 28) {
                    if selectedTab == .overview {
                        StudentHeaderView(
                            fullName: student.fullName,
                            levelDisplay: student.level.rawValue,
                            levelColor: levelColor,
                            initials: initials
                        )
                        .padding(.top, 36)

                        if isEditing {
                            editForm
                        } else {
                            StudentInfoRowsView(
                                birthdayText: formattedBirthday,
                                startDateText: student.dateStarted.map { Self.birthdayFormatter.string(from: $0) },
                                ageText: ageDescription,
                                gradeText: FloridaGradeCalculator.grade(for: student.birthday).displayString
                            )

                            Divider()
                                .padding(.top, 8)

                            WorkingOnListView(
                                isLoading: isLoadingWorks,
                                works: worksForStudent,
                                countText: "\(worksForStudent.count)",
                                titleForWork: { work in workTitle(for: work) },
                                subtitleForWork: { work in workSubtitle(for: work) },
                                iconAndColorForType: { type in iconAndColor(for: type) }
                            )

                            Divider()
                                .padding(.top, 8)

                            NextLessonsListView(
                                isLoading: isLoadingLessons,
                                lessons: nextLessonsForStudent,
                                countText: "\(nextLessonsForStudent.count)",
                                lessonName: { sl in lessonName(for: sl) },
                                lessonSubject: { sl in lessonSubject(for: sl) }
                            )
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
        .task(id: student.id) {
            await loadStudentData()
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
        .sheet(item: $selectedLessonForGive, onDismiss: { Task { await loadStudentData() } }) { l in
            GiveLessonSheet(lesson: l, preselectedStudentIDs: [student.id], startGiven: giveStartGiven) {
                selectedLessonForGive = nil
            }
            #if os(macOS)
            .frame(minWidth: 720, minHeight: 640)
            .presentationSizing(.fitted)
            #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .sheet(item: $selectedWorkForDetail, onDismiss: { Task { await loadStudentData() } }) { w in
            WorkDetailView(work: w) {
                selectedWorkForDetail = nil
            }
            #if os(macOS)
            .frame(minWidth: 720, minHeight: 640)
            .presentationSizing(.fitted)
            #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .sheet(item: $selectedStudentLessonForDetail, onDismiss: { Task { await loadStudentData() } }) { sl in
            StudentLessonDetailView(studentLesson: sl) {
                selectedStudentLessonForDetail = nil
            }
            #if os(macOS)
            .frame(minWidth: 720, minHeight: 640)
            .presentationSizing(.fitted)
            #else
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            #endif
        }
        .onAppear { ensureChecklistSubjectSelection() }
        .onChange(of: lessons.map { $0.id }) { _ in ensureChecklistSubjectSelection() }
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

    @MainActor
    private func loadStudentData() async {
        isLoadingLessons = true
        isLoadingWorks = true
        defer {
            isLoadingLessons = false
            isLoadingWorks = false
        }

        let sid = student.id

        do {
            // Fetch upcoming StudentLesson broadly, then filter in-memory for this student
            let upcomingDescriptor = FetchDescriptor<StudentLesson>(predicate: #Predicate { $0.givenAt == nil })
            let allUpcoming = try modelContext.fetch(upcomingDescriptor)
            let fetchedSL = allUpcoming.filter { $0.studentIDs.contains(sid) }

            // Sort to match previous logic
            let sortedSL = fetchedSL.sorted { lhs, rhs in
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
            }
            nextLessonsForStudent = sortedSL.map { $0.snapshot() }

            // Fetch all works and filter for this student
            let allWorks = try modelContext.fetch(FetchDescriptor<WorkModel>())
            let filteredWorks = allWorks.filter { $0.studentIDs.contains(sid) }
            worksForStudent = filteredWorks.sorted { $0.createdAt > $1.createdAt }

            // Prefetch student lessons referenced by works
            let workSLIDs = Set(worksForStudent.compactMap { $0.studentLessonID })
            if workSLIDs.isEmpty {
                studentLessonsByID = [:]
            } else {
                do {
                    let slPredicate = #Predicate<StudentLesson> { workSLIDs.contains($0.id) }
                    let slDescriptor = FetchDescriptor<StudentLesson>(predicate: slPredicate)
                    let sls = try modelContext.fetch(slDescriptor)
                    studentLessonsByID = Dictionary(uniqueKeysWithValues: sls.map { ($0.id, $0) })
                } catch {
                    // Fallback: fetch all and filter in-memory
                    let sls = try modelContext.fetch(FetchDescriptor<StudentLesson>())
                    let filtered = sls.filter { workSLIDs.contains($0.id) }
                    studentLessonsByID = Dictionary(uniqueKeysWithValues: filtered.map { ($0.id, $0) })
                }
            }

            // Prefetch referenced lessons (from upcoming nextLessons and from work-linked student lessons)
            let lessonIDsFromNext = Set(sortedSL.map { $0.lessonID })
            let lessonIDsFromWorks = Set(studentLessonsByID.values.map { $0.lessonID })
            let allLessonIDs = lessonIDsFromNext.union(lessonIDsFromWorks)
            if allLessonIDs.isEmpty {
                lessonsByID = [:]
            } else {
                do {
                    let lPredicate = #Predicate<Lesson> { lesson in
                        allLessonIDs.contains(lesson.id)
                    }
                    let lDescriptor = FetchDescriptor<Lesson>(predicate: lPredicate)
                    let lessons = try modelContext.fetch(lDescriptor)
                    lessonsByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
                } catch {
                    // Fallback: fetch all lessons and filter in-memory
                    let allLessons = try modelContext.fetch(FetchDescriptor<Lesson>())
                    let filtered = allLessons.filter { allLessonIDs.contains($0.id) }
                    lessonsByID = Dictionary(uniqueKeysWithValues: filtered.map { ($0.id, $0) })
                }
            }
        } catch {
            // If fetch fails, leave arrays empty; UI will show empty state
            nextLessonsForStudent = []
            worksForStudent = []
            lessonsByID = [:]
            studentLessonsByID = [:]
        }
    }

    private static let birthdayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .long
        df.timeStyle = .none
        return df
    }()

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

