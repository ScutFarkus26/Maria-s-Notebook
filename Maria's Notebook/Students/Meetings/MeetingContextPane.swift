// MeetingContextPane.swift
// Interactive context pane showing student work snapshot, lessons, and meeting history

import SwiftUI
import CoreData
import OSLog

// MARK: - Context Pane

struct MeetingContextPane: View {
    let student: CDStudent
    let openWork: [CDWorkModel]
    let overdueWork: [CDWorkModel]
    let recentCompleted: [CDWorkModel]
    let lessonsSinceLastMeeting: [CDLessonAssignment]
    let meetings: [CDStudentMeeting]
    let lessonsByID: [UUID: CDLesson]
    var isCompact: Bool = false

    // Work review bindings from MeetingSessionView
    @Binding var workReviewDrafts: [UUID: String]
    @Binding var reviewedWorkIDs: Set<UUID>

    @Environment(\.managedObjectContext) private var viewContext

    @State private var selectedWorkID: UUID?
    @State private var isContextCollapsed: Bool = false
    @State private var showAllOpenWork: Bool = false
    @State private var popoverMeeting: CDStudentMeeting?
    @State private var showAllMeetings: Bool = false
    @State private var meetingToDelete: CDStudentMeeting?
    @State private var expandedWorkID: UUID?
    @State private var restingDatePickerWorkID: UUID?
    @State private var restingDate: Date = Calendar.current.date(byAdding: .weekOfYear, value: 2, to: Date()) ?? Date()
    @State private var rescheduleWorkID: UUID?
    @State private var rescheduleDate: Date = Date()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "MariasNotebook",
        category: "MeetingContextPane"
    )

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                if isCompact {
                    Button {
                        adaptiveWithAnimation { isContextCollapsed.toggle() }
                    } label: {
                        HStack {
                            Text("Student Context")
                                .font(.headline)
                            Spacer()
                            Image(systemName: isContextCollapsed ? "chevron.down" : "chevron.up")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                if !isCompact || !isContextCollapsed {
                    // Work Snapshot
                    workSnapshotSection

                    // Lessons Since Last Meeting
                    lessonsSinceSection

                    // Meeting History Preview
                    meetingHistorySection
                }
            }
            .padding()
        }
        .sheet(item: Binding(
            get: { selectedWorkID.map { WorkIDWrapper(id: $0) } },
            set: { selectedWorkID = $0?.id }
        )) { wrapper in
            WorkDetailView(
                workID: wrapper.id,
                onDone: { selectedWorkID = nil },
                showRepresentButton: true
            )
        }
        .sheet(item: $popoverMeeting) { meeting in
            MeetingDetailSheet(meeting: meeting)
        }
        .confirmationDialog(
            "Delete Meeting?",
            isPresented: Binding(
                get: { meetingToDelete != nil },
                set: { if !$0 { meetingToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let meeting = meetingToDelete {
                    deleteMeeting(meeting)
                }
            }
        }
    }

    // MARK: - Helper for sheet binding

    private struct WorkIDWrapper: Identifiable {
        let id: UUID
    }

    // MARK: - Work Snapshot Section

    private var workSnapshotSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Work Snapshot", icon: "tray.full")

            HStack(spacing: 16) {
                statBox(title: "Open", count: openWork.count, color: .blue)
                statBox(title: "Overdue", count: overdueWork.count, color: .orange)
                statBox(title: "Completed", count: recentCompleted.count, color: .green)
            }

            if !overdueWork.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overdue/Stuck")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColors.warning)

                    ForEach(overdueWork.prefix(3)) { work in
                        workCard(work)
                    }
                }
            }

            if !openWork.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Open Work")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)

                        Spacer()

                        if openWork.count > 5 {
                            Button {
                                adaptiveWithAnimation {
                                    showAllOpenWork.toggle()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(showAllOpenWork ? "Show Less" : "Show All (\(openWork.count))")
                                        .font(.caption)
                                    Image(systemName: showAllOpenWork ? "chevron.up" : "chevron.down")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    ForEach(showAllOpenWork ? openWork : Array(openWork.prefix(5))) { work in
                        workCard(work)
                    }
                }
            }
        }
        .padding(12)
        .background(cardBackground)
    }

    private func statBox(title: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
                .font(.title2.weight(.semibold))
                .foregroundStyle(count > 0 ? color : .secondary)

            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(UIConstants.OpacityConstants.light))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Interactive Work Card

    private func workCard(_ work: CDWorkModel) -> some View {
        let workID = work.id ?? UUID()
        let isExpanded = expandedWorkID == workID
        let isReviewed = reviewedWorkIDs.contains(workID)

        return VStack(alignment: .leading, spacing: 0) {
            // Collapsed header — always visible
            Button {
                adaptiveWithAnimation {
                    expandedWorkID = isExpanded ? nil : workID
                }
            } label: {
                HStack(spacing: 6) {
                    if isReviewed {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(AppColors.success)
                    } else {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary)
                    }

                    Text(workDisplayTitle(work))
                        .font(.footnote)
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if work.isResting {
                        Text("resting")
                            .font(.caption2)
                            .foregroundStyle(.purple)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(Color.purple.opacity(0.15)))
                    }

                    Spacer()

                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)
            .padding(.vertical, 4)

            // Expanded inline review controls
            if isExpanded {
                expandedWorkControls(work, workID: workID)
                    .padding(.leading, 14)
                    .padding(.bottom, 8)
            }
        }
    }

    // MARK: - Expanded Work Controls

    private func expandedWorkControls(_ work: CDWorkModel, workID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Status picker
            HStack(spacing: 8) {
                Text("Status")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker("Status", selection: Binding(
                    get: { work.status },
                    set: { newStatus in
                        work.status = newStatus
                        if newStatus == .complete {
                            work.completedAt = Date()
                        }
                        markReviewed(workID)
                        trySave()
                    }
                )) {
                    Text("Active").tag(WorkStatus.active)
                    Text("Review").tag(WorkStatus.review)
                    Text("Complete").tag(WorkStatus.complete)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }

            // Completion outcome (only if complete)
            if work.status == .complete {
                HStack(spacing: 8) {
                    Text("Outcome")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("Outcome", selection: Binding(
                        get: { work.completionOutcome ?? .proficient },
                        set: { newOutcome in
                            work.completionOutcome = newOutcome
                            trySave()
                        }
                    )) {
                        Text("Proficient").tag(CompletionOutcome.proficient)
                        Text("Needs Practice").tag(CompletionOutcome.needsMorePractice)
                        Text("Needs Review").tag(CompletionOutcome.needsReview)
                    }
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }

            // Review note
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Note...", text: Binding(
                    get: { workReviewDrafts[workID] ?? "" },
                    set: { newValue in
                        workReviewDrafts[workID] = newValue
                        markReviewed(workID)
                    }
                ))
                .font(.caption)
                .textFieldStyle(.roundedBorder)
            }

            // Quick actions
            HStack(spacing: 12) {
                // Clear overdue
                Button {
                    work.lastTouchedAt = Date()
                    markReviewed(workID)
                    trySave()
                } label: {
                    Label("Clear Overdue", systemImage: "clock.badge.checkmark")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                // Rest / Un-rest
                if work.isResting {
                    Button {
                        MeetingReviewService.clearWorkResting(work)
                        markReviewed(workID)
                        trySave()
                    } label: {
                        Label("Wake Up", systemImage: "sun.max")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button {
                        restingDatePickerWorkID = workID
                        restingDate = Calendar.current.date(byAdding: .weekOfYear, value: 2, to: Date()) ?? Date()
                    } label: {
                        Label("Let Rest", systemImage: "moon.zzz")
                            .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .popover(isPresented: Binding(
                        get: { restingDatePickerWorkID == workID },
                        set: { if !$0 { restingDatePickerWorkID = nil } }
                    )) {
                        VStack(spacing: 12) {
                            Text("Rest until...")
                                .font(.subheadline.weight(.medium))
                            DatePicker("", selection: $restingDate, in: Date()..., displayedComponents: .date)
                                .datePickerStyle(.graphical)
                                .frame(maxWidth: 300)
                            Button("Confirm") {
                                MeetingReviewService.setWorkResting(work, until: restingDate)
                                markReviewed(workID)
                                trySave()
                                restingDatePickerWorkID = nil
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    }
                }

                // Open full detail
                Button {
                    selectedWorkID = workID
                } label: {
                    Label("Details", systemImage: "arrow.up.right.square")
                        .font(.caption2)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func markReviewed(_ workID: UUID) {
        reviewedWorkIDs.insert(workID)
    }

    private func trySave() {
        do {
            try viewContext.save()
        } catch {
            Self.logger.warning("Failed to save work changes: \(error)")
        }
    }

    private func workDisplayTitle(_ work: CDWorkModel) -> String {
        let title = work.title.trimmed()
        if !title.isEmpty { return title }
        return lessonsByID[uuidString: work.lessonID]?.name ?? "Lesson"
    }

    // MARK: - Lessons Since Section

    private var lessonsSinceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader("Lessons Since Last Meeting", icon: "book")

            if lessonsSinceLastMeeting.isEmpty {
                Text("No lessons since last meeting")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(lessonsSinceLastMeeting.prefix(8)) { la in
                    lessonRow(la)
                }

                if lessonsSinceLastMeeting.count > 8 {
                    Text("+ \(lessonsSinceLastMeeting.count - 8) more")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(cardBackground)
    }

    private func lessonRow(_ la: CDLessonAssignment) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "book.fill")
                .font(.system(size: 8))
                .foregroundStyle(.secondary)

            if let lesson = la.lesson {
                Text(lesson.name)
                    .font(.footnote)
                    .foregroundStyle(.primary)
            } else if let lesson = lessonsByID[uuidString: la.lessonID] {
                Text(lesson.name)
                    .font(.footnote)
                    .foregroundStyle(.primary)
            } else {
                Text("Lesson")
                    .font(.footnote)
                    .foregroundStyle(.primary)
            }

            Spacer()

            if let presentedAt = la.presentedAt {
                Text(presentedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Meeting History Section

    private var meetingHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionHeader("Recent Meetings", icon: "clock")

                Spacer()

                if meetings.count > 3 {
                    Button {
                        adaptiveWithAnimation {
                            showAllMeetings.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(showAllMeetings ? "Show Less" : "Show All (\(meetings.count))")
                                .font(.caption)
                            Image(systemName: showAllMeetings ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if meetings.isEmpty {
                Text("No prior meetings")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                let visibleMeetings = showAllMeetings ? meetings : Array(meetings.prefix(3))
                ForEach(visibleMeetings) { meeting in
                    meetingHistoryRow(meeting)
                }
            }
        }
        .padding(12)
        .background(cardBackground)
    }

    private func meetingHistoryRow(_ meeting: CDStudentMeeting) -> some View {
        Button {
            popoverMeeting = meeting
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text((meeting.date ?? Date()).formatted(date: .abbreviated, time: .omitted))
                            .font(.footnote.weight(.medium))

                        if meeting.completed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(AppColors.success)
                        }
                    }

                    if !meeting.focus.trimmed().isEmpty {
                        Text(meeting.focus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    // Show work review count if any
                    let reviewCount = (meeting.workReviews?.count ?? 0)
                    if reviewCount > 0 {
                        Text("\(reviewCount) work item\(reviewCount == 1 ? "" : "s") reviewed")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .padding(.vertical, 4)
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) {
                meetingToDelete = meeting
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.primary)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
    }

    private func deleteMeeting(_ meeting: CDStudentMeeting) {
        adaptiveWithAnimation {
            viewContext.delete(meeting)
            do {
                try viewContext.save()
            } catch {
                Self.logger.warning("Failed to save after deleting meeting: \(error)")
            }
        }
    }
}
