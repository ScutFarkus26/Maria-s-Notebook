import SwiftUI
import SwiftData

struct LessonProgressSection: View {
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext

    private enum PresentedMode { case none, just, previous }

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
    @State private var showJustPresentedFlash = false
    @State private var actionBounceID = UUID()
    @State private var presentedMode: PresentedMode = .none

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            progressCard
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

    private var progressCard: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                // State chips row
                HStack(spacing: 10) {
                    // Just Presented
                    Button {
                        isPresented = true
                        givenAt = calendar.startOfDay(for: Date())
                        presentedMode = .just
                        showJustPresentedFlash = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                            showJustPresentedFlash = false
                        }
                    } label: {
                        StatusChip(
                            title: "Just Presented",
                            systemImage: "checkmark.circle.fill",
                            tint: .green,
                            active: presentedMode == .just
                        )
                    }
                    .buttonStyle(.plain)
                    .sensoryFeedback(.success, trigger: showJustPresentedFlash)

                    // Previously Presented
                    Button {
                        isPresented = true
                        // Date is optional; leave as-is until chosen
                        presentedMode = .previous
                    } label: {
                        StatusChip(
                            title: "Previously Presented",
                            systemImage: "clock.badge.checkmark",
                            tint: .green,
                            active: presentedMode == .previous
                        )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    if presentedMode == .previous && isPresented {
                        Button {
                            presentedDate = calendar.startOfDay(for: givenAt ?? Date())
                            showPresentedPopover.toggle()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "calendar")
                                if let date = givenAt {
                                    Text(date, style: .date)
                                } else {
                                    Text("Add Date")
                                }
                            }
                            .font(.caption)
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

                // Bottom row: Needs another presentation aligned right
                HStack {
                    Spacer()
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

                // Hairline divider
                Divider().overlay(Color.white.opacity(0.06))

                // Actions row
                HStack(spacing: 12) {
                    ActionPill(
                        title: "Add Practice",
                        systemImage: "arrow.triangle.2.circlepath",
                        tint: .purple
                    ) {
                        addPracticeIfNeeded()
                    }

                    ActionPill(
                        title: "Add Follow‑Up",
                        systemImage: "plus",
                        tint: .yellow
                    ) {
                        followUpDraft = ""
                        showFollowUpSheet = true
                    }
                    
                    Spacer()
                }

                // Next in group suggestion
                if isPresented, let next = nextLessonInGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle")
                                .foregroundStyle(.blue)
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
                    .transition(.opacity)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.green.opacity(showJustPresentedFlash ? 0.5 : 0.0), lineWidth: 2)
            )
            .animation(.easeInOut(duration: 0.6), value: showJustPresentedFlash)
            .onAppear {
                if isPresented {
                    if let date = givenAt, calendar.isDateInToday(date) {
                        presentedMode = .just
                    } else {
                        presentedMode = .previous
                    }
                } else {
                    presentedMode = .none
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

private struct GlassCard<Content: View>: View {
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    var body: some View {
        content()
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    .blendMode(.overlay)
            )
            .shadow(color: .black.opacity(0.25), radius: 20, y: 10)
    }
}

private struct StatusChip: View {
    let title: String
    let systemImage: String
    let tint: Color
    var active: Bool = true

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .foregroundStyle(tint)
        .background(
            Capsule(style: .continuous)
                .fill(tint.opacity(active ? 0.20 : 0.10))
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(0.35), lineWidth: 1)
        )
        .contentTransition(.opacity)
        .animation(.spring(response: 0.25, dampingFraction: 0.9), value: active)
    }
}

private struct ActionPill: View {
    let title: String
    let systemImage: String
    let tint: Color
    let action: () -> Void
    @State private var bounce = false

    var body: some View {
        Button {
            bounce.toggle()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.callout.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .symbolEffect(.bounce, value: bounce)
    }
}

