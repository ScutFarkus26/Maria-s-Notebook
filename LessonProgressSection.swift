import SwiftUI
import SwiftData

struct LessonProgressSection: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext

    let subjectColor: Color

    @Binding var isPresented: Bool
    @Binding var givenAt: Date?
    @Binding var needsAnotherPresentation: Bool

    @Binding var selectedStudentIDs: Set<UUID>

    let lesson: Lesson?
    let nextLessonInGroup: Lesson?
    let studentLessonID: UUID

    let studentsAll: [Student]
    let lessonsAll: [Lesson]
    let studentLessonsAll: [StudentLesson]

    // Banners
    @Binding var didPlanNext: Bool
    @Binding var showPlannedBanner: Bool

    // Follow-up sheet
    @Binding var showFollowUpSheet: Bool
    @Binding var followUpDraft: String

    // Quick banners
    @Binding var showQuickBanner: Bool
    @Binding var quickBannerText: String
    @Binding var quickBannerColor: Color

    // Local UI state
    @State private var showPresentedPopover = false
    @State private var presentedDate: Date = Date()
    @State private var showRePresentPopover = false
    @State private var rePresentDate: Date = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            content
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .foregroundStyle(.secondary)
                .font(.system(size: 16))
            Text("Lesson Progress")
                .font(.system(size: AppTheme.FontSize.callout, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            presentedRow
            practiceRow
            rePresentRow
            followUpRow
            nextLessonRow
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private var presentedRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle(isOn: $isPresented) {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(isPresented ? .green : .secondary)
                            .font(.system(size: 18))
                        Text("Presented")
                            .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                    }
                }
                .toggleStyle(.button)
                .buttonStyle(.borderless)
                .tint(.green)

                Spacer()

                if isPresented {
                    Button {
                        presentedDate = calendar.startOfDay(for: givenAt ?? Date())
                        showPresentedPopover.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            if let date = givenAt {
                                Text(date, style: .date)
                                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                            } else {
                                Text("Add Date")
                                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                            }
                            Image(systemName: "calendar")
                                .font(.system(size: 12))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showPresentedPopover, arrowEdge: .top) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Presentation Date")
                                .font(.headline)
                            DatePicker("Date", selection: $presentedDate, displayedComponents: [.date])
                            #if os(macOS)
                            .datePickerStyle(.field)
                            #else
                            .datePickerStyle(.compact)
                            #endif
                            HStack {
                                Button("Clear") {
                                    givenAt = nil
                                    showPresentedPopover = false
                                }
                                Spacer()
                                Button("Set") {
                                    givenAt = calendar.startOfDay(for: presentedDate)
                                    showPresentedPopover = false
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .padding(12)
                        .frame(minWidth: 280)
                    }
                }
            }
        }
    }

    private var practiceRow: some View {
        HStack {
            Button {
                addPracticeIfNeeded()
            } label: {
                Label("Add Practice", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
            }
            .buttonStyle(.bordered)
            Spacer()
        }
    }

    private var rePresentRow: some View {
        HStack {
            Toggle(isOn: $needsAnotherPresentation) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise.circle.fill")
                        .foregroundStyle(needsAnotherPresentation ? .orange : .secondary)
                        .font(.system(size: 18))
                    Text("Needs Another Presentation")
                        .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                }
            }
            .toggleStyle(.button)
            .buttonStyle(.borderless)
            .tint(.orange)

            Spacer()

            if needsAnotherPresentation {
                Button {
                    rePresentDate = defaultRePresentDate()
                    showRePresentPopover.toggle()
                } label: {
                    Label("Schedule", systemImage: "calendar.badge.clock")
                        .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
                }
                .buttonStyle(.bordered)
                .popover(isPresented: $showRePresentPopover, arrowEdge: .top) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Schedule Re-presentation")
                            .font(.headline)
                        DatePicker("Date", selection: $rePresentDate, displayedComponents: [.date])
                        #if os(macOS)
                        .datePickerStyle(.field)
                        #else
                        .datePickerStyle(.compact)
                        #endif
                        HStack {
                            Spacer()
                            Button("Schedule") {
                                scheduleRePresent(on: rePresentDate)
                                showRePresentPopover = false
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .padding(12)
                    .frame(minWidth: 280)
                }
            }
        }
    }

    private var followUpRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.yellow)
                    .font(.system(size: 16))
                Text("Follow-Up Work")
                    .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
            }

            Button {
                followUpDraft = ""
                showFollowUpSheet = true
            } label: {
                Label("Add Follow-Up…", systemImage: "plus")
                    .font(.system(size: AppTheme.FontSize.callout, design: .rounded))
            }
            .buttonStyle(.bordered)
        }
    }

    private var nextLessonRow: some View {
        Group {
            if isPresented, let next = nextLessonInGroup {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.right.circle")
                            .foregroundStyle(.blue)
                            .font(.system(size: 16))
                        Text("Next in Group: \(next.name)")
                            .font(.system(size: AppTheme.FontSize.body, weight: .medium, design: .rounded))
                    }

                    Button {
                        planNextLessonInGroup()
                    } label: {
                        Label("Plan Next Lesson", systemImage: "calendar.badge.plus")
                            .font(.system(size: AppTheme.FontSize.callout, design: .rounded))
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(didPlanNext || studentLessonsAll.contains { sl in
                        sl.resolvedLessonID == next.id && Set(sl.resolvedStudentIDs) == Set(selectedStudentIDs) && sl.givenAt == nil
                    })
                }
            }
        }
    }

    // MARK: - Actions
    private func addPracticeIfNeeded() {
        let hasPracticeWork: Bool = {
            let descriptor = FetchDescriptor<WorkModel>()
            let works = (try? modelContext.fetch(descriptor)) ?? []
            return works.contains { work in
                work.studentLessonID == studentLessonID && work.workType == .practice
            }
        }()
        if !hasPracticeWork {
            let practiceWork = WorkModel(
                id: UUID(),
                title: "Practice: \(lesson?.name ?? "Lesson")",
                workType: .practice,
                studentLessonID: studentLessonID,
                notes: "",
                createdAt: Date()
            )
            practiceWork.participants = Array(selectedStudentIDs).map { sid in WorkParticipantEntity(studentID: sid, completedAt: nil, work: practiceWork) }
            modelContext.insert(practiceWork)
            try? modelContext.save()
        }
        showBanner(text: "Practice added", color: .purple)
    }

    private func scheduleRePresent(on date: Date) {
        let startOfDay = calendar.startOfDay(for: date)
        let scheduled = calendar.date(byAdding: .hour, value: 9, to: startOfDay) ?? startOfDay

        let newStudentLesson = StudentLesson(
            id: UUID(),
            lessonID: lesson?.id ?? UUID(),
            studentIDs: Array(selectedStudentIDs),
            createdAt: Date(),
            scheduledFor: scheduled,
            givenAt: nil,
            notes: "",
            needsPractice: false,
            needsAnotherPresentation: false,
            followUpWork: ""
        )
        newStudentLesson.students = studentsAll.filter { selectedStudentIDs.contains($0.id) }
        newStudentLesson.lesson = lesson
        modelContext.insert(newStudentLesson)

        do { try modelContext.save() } catch {}

        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        showBanner(text: "Re-present scheduled for \(fmt.string(from: scheduled))", color: .blue)
    }

    private func defaultRePresentDate() -> Date {
        let base = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return calendar.startOfDay(for: base)
    }

    private func planNextLessonInGroup() {
        guard let next = nextLessonInGroup else { return }
        let sameStudents = Set(selectedStudentIDs)
        let exists = studentLessonsAll.contains { sl in
            sl.resolvedLessonID == next.id && Set(sl.resolvedStudentIDs) == sameStudents && sl.givenAt == nil
        }
        if !exists {
            let newStudentLesson = StudentLesson(
                id: UUID(),
                lessonID: next.id,
                studentIDs: Array(selectedStudentIDs),
                createdAt: Date(),
                scheduledFor: nil,
                givenAt: nil,
                notes: "",
                needsPractice: false,
                needsAnotherPresentation: false,
                followUpWork: ""
            )
            newStudentLesson.students = studentsAll.filter { sameStudents.contains($0.id) }
            newStudentLesson.lesson = lessonsAll.first(where: { $0.id == next.id })
            modelContext.insert(newStudentLesson)
            try? modelContext.save()
        }
        didPlanNext = true
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { showPlannedBanner = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { showPlannedBanner = false }
    }

    private func showBanner(text: String, color: Color = .green, autoHideAfter seconds: Double = 2.0) {
        quickBannerText = text
        quickBannerColor = color
        withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            showQuickBanner = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
            withAnimation(.easeInOut(duration: 0.2)) { showQuickBanner = false }
        }
    }
}
