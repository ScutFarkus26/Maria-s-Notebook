// swiftlint:disable file_length
// LessonProgressSection.swift
// UI section for managing presentation state and quick actions within Presentation detail.
// Behavior-preserving cleanup: comments, MARKs, and small helpers docs.

import OSLog
import SwiftUI
import SwiftData

// Presents lesson progress controls (presented state, needs another presentation, quick actions).
// Safe refactor adds structure and docs only.
// swiftlint:disable:next type_body_length
struct LessonProgressSection: View {
    private static let logger = Logger.lessons
    // MARK: - Environment
    @Environment(\.calendar) private var calendar
    @Environment(\.modelContext) private var modelContext

    // MARK: - Local Types
    private enum PresentedMode { case none, just, previous }

    // MARK: - Inputs
    let subjectColor: Color

    @Binding var isPresented: Bool
    @Binding var givenAt: Date?
    @Binding var needsAnotherPresentation: Bool

    @Binding var selectedStudentIDs: Set<UUID>

    let lesson: Lesson?
    let nextLessonInGroup: Lesson?
    let presentationID: UUID

    let studentsAll: [Student]
    let lessonsAll: [Lesson]
    let lessonAssignmentsAll: [LessonAssignment]

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

    // MARK: - Local UI State
    @State private var showPresentedPopover = false
    @State private var presentedDate: Date = Date()
    @State private var showRePresentPopover = false
    @State private var rePresentDate: Date = Date()
    @State private var showJustPresentedFlash = false
    @State private var actionBounceID = UUID()
    @State private var presentedMode: PresentedMode = .none

    // MARK: - Body
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            progressCard
        }
    }

    // MARK: - Subviews
    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.seal")
                .foregroundStyle(.secondary)
                .font(.system(size: 16))
            Text("Lesson Progress")
                .font(AppTheme.ScaledFont.calloutSemibold)
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
                        Task { @MainActor in
                            do {
                                try await Task.sleep(for: .milliseconds(800))
                                showJustPresentedFlash = false
                            } catch {
                                Self.logger.warning("Task sleep failed: \(error)")
                            }
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
                                .font(AppTheme.ScaledFont.bodySemibold)
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
                                .font(AppTheme.ScaledFont.caption)
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
                                .font(AppTheme.ScaledFont.bodySemibold)
                        }
                        Button {
                            planNextLessonInGroup()
                        } label: {
                            Label("Plan Next Lesson", systemImage: "calendar.badge.plus")
                                .font(AppTheme.ScaledFont.callout)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(didPlanNext || lessonAssignmentsAll.contains { la in
                            la.resolvedLessonID == next.id
                                && Set(la.resolvedStudentIDs) == Set(selectedStudentIDs)
                                && !la.isPresented
                        })
                    }
                    .transition(.opacity)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Color.green.opacity(showJustPresentedFlash ? 0.5 : 0.0), lineWidth: 2)
            )
            .adaptiveAnimation(.easeInOut(duration: 0.6), value: showJustPresentedFlash)
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
    // swiftlint:disable:next function_body_length
    private func addPracticeIfNeeded() {
        let hasPracticeWork: Bool = {
            let descriptor = FetchDescriptor<WorkModel>()
            let works: [WorkModel]
            do {
                works = try modelContext.fetch(descriptor)
            } catch {
                Self.logger.warning("Failed to fetch work: \(error)")
                works = []
            }
            return works.contains { work in
                // Check using kind
                let isPractice = (work.kind ?? .research) == .practiceLesson
                return work.studentLessonID == presentationID && isPractice
            }
        }()
        if !hasPracticeWork {
            let practiceWork = WorkModel(
                id: UUID(),
                title: "Practice: \(lesson?.name ?? "Lesson")",
                kind: .practiceLesson,
                studentLessonID: presentationID,
                createdAt: Date()
            )
            // Set identity fields
            if let lessonID = lesson?.id {
                practiceWork.lessonID = lessonID.uuidString
            } else {
                // Try to get lessonID from the LessonAssignment
                var descriptor = FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == presentationID })
                descriptor.fetchLimit = 1
                do {
                    if let la = try modelContext.fetch(descriptor).first {
                        practiceWork.lessonID = la.lessonID
                    }
                } catch {
                    Self.logger.warning("Failed to fetch lesson assignment for lessonID: \(error)")
                }
            }
            if let firstStudentID = selectedStudentIDs.first {
                practiceWork.studentID = firstStudentID.uuidString
            } else {
                // Try to get studentID from the LessonAssignment
                var descriptor = FetchDescriptor<LessonAssignment>(predicate: #Predicate { $0.id == presentationID })
                descriptor.fetchLimit = 1
                do {
                    if let la = try modelContext.fetch(descriptor).first,
                       let firstStudentID = la.resolvedStudentIDs.first {
                        practiceWork.studentID = firstStudentID.uuidString
                    }
                } catch {
                    Self.logger.warning("Failed to fetch lesson assignment for studentID: \(error)")
                }
            }
            practiceWork.legacyStudentLessonID = presentationID.uuidString
            practiceWork.participants = Array(selectedStudentIDs).map { sid in
                WorkParticipantEntity(studentID: sid, completedAt: nil, work: practiceWork)
            }
            modelContext.insert(practiceWork)
            do {
                try modelContext.save()
            } catch {
                Self.logger.warning("Failed to save context: \(error)")
            }
        }
        showBanner(text: "Practice added", color: .purple)
    }

    private func scheduleRePresent(on date: Date) {
        guard let lesson = lesson else { return }
        
        let startOfDay = calendar.startOfDay(for: date)
        let scheduled = calendar.date(byAdding: .hour, value: 9, to: startOfDay) ?? startOfDay

        let newLA = PresentationFactory.makeScheduled(
            lessonID: lesson.id,
            studentIDs: Array(selectedStudentIDs),
            scheduledFor: scheduled
        )
        newLA.lesson = lesson
        newLA.students = studentsAll.filter { selectedStudentIDs.contains($0.id) }
        newLA.syncSnapshotsFromRelationships()
        modelContext.insert(newLA)

        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save context after scheduling re-presentation: \(error)")
        }

        // Auto-enroll students in track if lesson belongs to a track
        GroupTrackService.autoEnrollInTrackIfNeeded(
            lesson: lesson,
            studentIDs: Array(selectedStudentIDs).map { $0.uuidString },
            modelContext: modelContext
        )

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
        let exists = lessonAssignmentsAll.contains { la in
            la.resolvedLessonID == next.id && Set(la.resolvedStudentIDs) == sameStudents && !la.isPresented
        }
        if !exists {
            let newLA = PresentationFactory.makeDraft(
                lessonID: next.id,
                studentIDs: Array(selectedStudentIDs)
            )
            newLA.lesson = lessonsAll.first(where: { $0.id == next.id })
            newLA.students = studentsAll.filter { sameStudents.contains($0.id) }
            newLA.syncSnapshotsFromRelationships()
            modelContext.insert(newLA)
            do {
                try modelContext.save()
            } catch {
                Self.logger.warning("Failed to save context after planning next lesson: \(error)")
            }
        }
        didPlanNext = true
        adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.9)) { showPlannedBanner = true }
        Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(2))
                showPlannedBanner = false
            } catch {
                Self.logger.warning("Task sleep failed: \(error)")
            }
        }
    }

    private func showBanner(text: String, color: Color = .green, autoHideAfter seconds: Double = 2.0) {
        quickBannerText = text
        quickBannerColor = color
        adaptiveWithAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
            showQuickBanner = true
        }
        Task { @MainActor in
            do {
                try await Task.sleep(for: .seconds(seconds))
                adaptiveWithAnimation(.easeInOut(duration: 0.15)) { showQuickBanner = false }
            } catch {
                Self.logger.warning("Task sleep failed: \(error)")
            }
        }
    }
}

/// Simple glass-like card container used within this section. Purely presentational.
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

/// Small state chip used for presented/previously presented toggles.
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
        .adaptiveAnimation(.spring(response: 0.25, dampingFraction: 0.9), value: active)
    }
}

/// Action pill button with subtle bounce effect. Used for quick actions.
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
