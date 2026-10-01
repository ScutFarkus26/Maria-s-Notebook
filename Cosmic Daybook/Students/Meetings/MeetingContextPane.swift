// MeetingContextPane.swift
// What happened since the last meeting: work needing a decision, open work,
// lessons given, and past meetings.

import SwiftUI
import CoreData

struct MeetingContextPane: View {
    let stuckWork: [CDWorkModel]
    let openWork: [CDWorkModel]
    let lessonsSince: [CDLessonAssignment]
    let meetings: [CDStudentMeeting]
    let lastMeetingDate: Date?
    @Bindable var draft: MeetingDraftModel
    let workTitle: (CDWorkModel) -> String
    let lessonName: (CDLessonAssignment) -> String
    let lessonArea: (CDLessonAssignment) -> String?
    var sections: Sections = .all

    /// Which parts to draw; a phone's sheets show one part at a time.
    struct Sections: OptionSet {
        let rawValue: Int
        static let decisions = Sections(rawValue: 1)
        static let openWork = Sections(rawValue: 2)
        static let lessons = Sections(rawValue: 4)
        static let meetings = Sections(rawValue: 8)
        static let all: Sections = [.decisions, .openWork, .lessons, .meetings]
    }

    @Environment(\.managedObjectContext) private var viewContext

    @State private var detailWorkID: UUID?
    @State private var expandedWorkID: UUID?
    @State private var meetingToShow: CDStudentMeeting?
    @State private var meetingToDelete: CDStudentMeeting?
    @State private var showAllMeetings = false

    private var decidedCount: Int {
        stuckWork.filter { $0.id.map(draft.reviewedWorkIDs.contains) ?? false }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if sections.contains(.decisions) && !stuckWork.isEmpty {
                decisionsSection
            }
            if sections.contains(.openWork) { openWorkSection }
            if sections.contains(.lessons) { lessonsSection }
            if sections.contains(.meetings) { meetingsSection }
        }
        .sheet(item: Binding(
            get: { detailWorkID.map(WorkIDWrapper.init) },
            set: { detailWorkID = $0?.id }
        )) { wrapper in
            WorkDetailView(workID: wrapper.id, onDone: { detailWorkID = nil }, showRepresentButton: true)
        }
        .sheet(item: $meetingToShow) { meeting in
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
                    adaptiveWithAnimation {
                        viewContext.delete(meeting)
                        viewContext.safeSave()
                    }
                }
            }
        }
    }

    private struct WorkIDWrapper: Identifiable {
        let id: UUID
    }

    // MARK: - Sections

    private var decisionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("Needs a Decision · \(decidedCount) of \(stuckWork.count) done")
            ForEach(stuckWork) { work in
                WorkDecisionCard(
                    work: work,
                    title: workTitle(work),
                    draft: draft,
                    onDetails: work.id.map { id in { detailWorkID = id } }
                )
            }
        }
    }

    private var openWorkSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Open Work · \(openWork.count)")
                .padding(.bottom, 6)
            if openWork.isEmpty {
                emptyLine("No open work")
            }
            ForEach(openWork) { work in
                if expandedWorkID != nil, expandedWorkID == work.id {
                    WorkDecisionCard(
                        work: work,
                        title: workTitle(work),
                        draft: draft,
                        onDetails: work.id.map { id in { detailWorkID = id } }
                    )
                    .padding(.vertical, 4)
                } else {
                    openWorkRow(work)
                }
            }
        }
    }

    private func openWorkRow(_ work: CDWorkModel) -> some View {
        let reviewed = work.id.map(draft.reviewedWorkIDs.contains) ?? false
        return Button {
            adaptiveWithAnimation { expandedWorkID = work.id }
        } label: {
            HStack(spacing: 8) {
                if reviewed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(AppColors.success)
                }
                Text(workTitle(work))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(statusText(work))
                    .font(.caption)
                    .foregroundStyle(work.isResting ? Color.purple : (work.status == .review ? Color.blue : .secondary))
            }
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var lessonsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(lessonsHeader)
            if lessonsSince.isEmpty {
                emptyLine("No lessons since the last meeting")
            }
            ForEach(lessonsSince) { assignment in
                HStack(spacing: 8) {
                    Circle()
                        .fill(lessonArea(assignment).map(AppColors.color(forArea:)) ?? Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(lessonName(assignment))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if let date = assignment.presentedAt ?? assignment.createdAt {
                        Text(DateFormatters.shortMonthDay.string(from: date))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var lessonsHeader: String {
        guard let lastMeetingDate else { return "Lessons This Year · \(lessonsSince.count)" }
        return "Lessons Since \(DateFormatters.shortMonthDay.string(from: lastMeetingDate)) · \(lessonsSince.count)"
    }

    private var meetingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionHeader("Past Meetings")
                Spacer()
                if meetings.count > 3 {
                    Button(showAllMeetings ? "Show Less" : "Show All (\(meetings.count))") {
                        adaptiveWithAnimation { showAllMeetings.toggle() }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            if meetings.isEmpty {
                emptyLine("No meetings yet")
            }
            ForEach(showAllMeetings ? meetings : Array(meetings.prefix(3))) { meeting in
                Button {
                    meetingToShow = meeting
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(DateFormatters.shortMonthDay.string(from: meeting.date ?? Date()))
                            .font(.caption.weight(.semibold))
                            .frame(width: 48, alignment: .leading)
                        Text(meeting.focus.trimmed().isEmpty ? "No focus recorded" : meeting.focus)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        meetingToDelete = meeting
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func statusText(_ work: CDWorkModel) -> String {
        if work.isResting, let until = work.restingUntil {
            return "Resting till \(DateFormatters.shortMonthDay.string(from: until))"
        }
        return work.status.displayName
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}
