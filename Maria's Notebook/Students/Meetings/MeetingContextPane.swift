// MeetingContextPane.swift
// Context pane showing student work snapshot, lessons, and meeting history

import SwiftUI
import SwiftData

// MARK: - Context Pane

struct MeetingContextPane: View {
    let student: Student
    let openWork: [WorkModel]
    let overdueWork: [WorkModel]
    let recentCompleted: [WorkModel]
    let lessonsSinceLastMeeting: [LessonAssignment]
    let meetings: [StudentMeeting]
    let lessonsByID: [UUID: Lesson]
    var isCompact: Bool = false

    @State private var selectedWorkID: UUID?
    @State private var isContextCollapsed: Bool = false
    @State private var showAllOpenWork: Bool = false

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
                        workRow(work)
                    }
                }
            }

            if !overdueWork.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Overdue/Stuck")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColors.warning)

                    ForEach(overdueWork.prefix(3)) { work in
                        workRow(work)
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

    private func workRow(_ work: WorkModel) -> some View {
        Button {
            selectedWorkID = work.id
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "circle.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(.secondary)

                Text(workDisplayTitle(work))
                    .font(.footnote)
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    private func workDisplayTitle(_ work: WorkModel) -> String {
        lessonsByID[uuidString: work.lessonID]?.name ?? "Lesson"
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

    private func lessonRow(_ la: LessonAssignment) -> some View {
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
            sectionHeader("Recent Meetings", icon: "clock")

            if meetings.isEmpty {
                Text("No prior meetings")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(meetings.prefix(3)) { meeting in
                    meetingHistoryRow(meeting)
                }
            }
        }
        .padding(12)
        .background(cardBackground)
    }

    private func meetingHistoryRow(_ meeting: StudentMeeting) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(meeting.date.formatted(date: .abbreviated, time: .omitted))
                    .font(.footnote.weight(.medium))

                if meeting.completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.success)
                }

                Spacer()
            }

            if !meeting.focus.trimmed().isEmpty {
                Text(meeting.focus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.primary)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.primary.opacity(0.04))
    }
}
