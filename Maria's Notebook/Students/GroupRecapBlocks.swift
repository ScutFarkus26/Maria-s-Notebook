// GroupRecapBlocks.swift
// Per-lesson row + presentation/work/check-in/note blocks shown inside the
// expanded GroupRecapStudentSection.

import SwiftUI

// MARK: - Per-Lesson Row

struct GroupRecapLessonRow: View {
    let entry: GroupRecapLessonEntry
    let subjectColor: Color

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if hasDetails {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                summaryRow
            }
            .buttonStyle(.plain)
            .disabled(!hasDetails)

            if isExpanded && hasDetails {
                detailContent
                    .padding(.top, 8)
                    .padding(.leading, 28)
                    .padding(.bottom, 4)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(rowBackground)
        )
    }

    private var rowBackground: Color {
        entry.isCurrentLesson ? subjectColor.opacity(0.08) : .clear
    }

    private var hasDetails: Bool {
        !entry.presentations.isEmpty
            || !entry.workItems.isEmpty
            || !entry.directNotes.isEmpty
            || !(entry.perStudentLessonNotes ?? "").isEmpty
    }

    private var summaryRow: some View {
        HStack(spacing: 8) {
            Image(systemName: chevronName)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 12)

            Text(entry.lessonName)
                .font(entry.isCurrentLesson
                    ? AppTheme.ScaledFont.bodyBold
                    : AppTheme.ScaledFont.body)
                .lineLimit(2)

            Spacer(minLength: 6)

            GroupRecapStateBadge(entry: entry)
            if let date = mostRecentDate {
                Text(date, format: .relative(presentation: .named))
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chevronName: String {
        if !hasDetails { return "circle.dotted" }
        return isExpanded ? "chevron.down" : "chevron.right"
    }

    private var mostRecentDate: Date? {
        if let m = entry.masteredAt { return m }
        if let l = entry.lastObservedAt { return l }
        if let f = entry.firstPresentedAt { return f }
        return entry.presentations.first?.presentedAt
            ?? entry.presentations.first?.scheduledFor
            ?? entry.workItems.first?.completedAt
            ?? entry.workItems.first?.assignedAt
    }

    @ViewBuilder
    private var detailContent: some View {
        if let perStudent = entry.perStudentLessonNotes, !perStudent.isEmpty {
            DetailLabeledBlock(label: "Lesson notes", text: perStudent)
        }
        ForEach(entry.presentations) { presentation in
            GroupRecapPresentationBlock(presentation: presentation)
        }
        ForEach(entry.workItems) { work in
            GroupRecapWorkBlock(work: work)
        }
        if !entry.directNotes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                ForEach(entry.directNotes) { note in
                    GroupRecapNoteBlock(note: note)
                }
            }
        }
    }
}

// MARK: - State Badge

struct GroupRecapStateBadge: View {
    let entry: GroupRecapLessonEntry

    var body: some View {
        Text(label)
            .font(AppTheme.ScaledFont.captionSmallSemibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }

    private var label: String {
        if let state = entry.outcomeState {
            switch state {
            case .presented: return "Presented"
            case .practicing: return "Practicing"
            case .readyForAssessment: return "Ready for Assessment"
            case .proficient: return "Mastered"
            }
        }
        return entry.presentations.isEmpty ? "Not yet presented" : "Presented"
    }

    private var color: Color {
        if let state = entry.outcomeState {
            switch state {
            case .presented: return .secondary
            case .practicing: return .blue
            case .readyForAssessment: return .orange
            case .proficient: return .green
            }
        }
        return entry.presentations.isEmpty ? .gray : .secondary
    }
}

// MARK: - Presentation Block

struct GroupRecapPresentationBlock: View {
    let presentation: GroupRecapPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.circle")
                    .foregroundStyle(.secondary)
                Text(headerText)
                    .font(AppTheme.ScaledFont.captionSemibold)
                Spacer(minLength: 0)
                if presentation.needsPractice {
                    GroupRecapFlagPill(label: "Needs practice", color: .blue)
                }
                if presentation.needsAnotherPresentation {
                    GroupRecapFlagPill(label: "Re-present", color: .orange)
                }
            }
            if !presentation.groupNotes.isEmpty {
                Text(presentation.groupNotes)
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.primary)
                    .padding(.leading, 22)
            }
            if !presentation.attachedNotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(presentation.attachedNotes) { note in
                        GroupRecapNoteBlock(note: note)
                    }
                }
                .padding(.leading, 22)
            }
        }
        .padding(.vertical, 4)
    }

    private var headerText: String {
        switch presentation.state {
        case .presented:
            if let date = presentation.presentedAt {
                return "Presented \(formatDate(date))"
            }
            return "Presented"
        case .scheduled:
            if let date = presentation.scheduledFor {
                return "Scheduled \(formatDate(date))"
            }
            return "Scheduled"
        case .draft:
            return "Draft"
        }
    }

    private func formatDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }
}

// MARK: - Work Block

struct GroupRecapWorkBlock: View {
    let work: GroupRecapWorkItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            workHeader
            if let dateLine {
                Text(dateLine)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
            }
            if !work.attachedNotes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(work.attachedNotes) { note in
                        GroupRecapNoteBlock(note: note)
                    }
                }
                .padding(.leading, 22)
            }
            if !work.checkIns.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(work.checkIns) { ci in
                        GroupRecapCheckInBlock(checkIn: ci)
                    }
                }
                .padding(.leading, 22)
            }
        }
        .padding(.vertical, 4)
    }

    private var workHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: work.kind?.iconName ?? "doc")
                .foregroundStyle(work.kind?.color ?? .secondary)
            Text(work.title.isEmpty ? "Untitled work" : work.title)
                .font(AppTheme.ScaledFont.captionSemibold)
            Spacer(minLength: 0)
            statusPill
            if let outcome = work.completionOutcome {
                outcomePill(outcome: outcome)
            }
        }
    }

    private var statusPill: some View {
        Text(work.status.displayName)
            .font(AppTheme.ScaledFont.captionSmallSemibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(work.status.color.opacity(0.18)))
            .foregroundStyle(work.status.color)
    }

    private func outcomePill(outcome: CompletionOutcome) -> some View {
        Text(outcome.displayName)
            .font(AppTheme.ScaledFont.captionSmallSemibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(outcome.color.opacity(0.18)))
            .foregroundStyle(outcome.color)
    }

    private var dateLine: String? {
        if let completed = work.completedAt {
            return "Completed \(completed.formatted(date: .abbreviated, time: .omitted))"
        }
        if let assigned = work.assignedAt {
            return "Assigned \(assigned.formatted(date: .abbreviated, time: .omitted))"
        }
        return nil
    }
}

// MARK: - Check-In Block

struct GroupRecapCheckInBlock: View {
    let checkIn: GroupRecapCheckIn

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: checkIn.status.iconName)
                    .foregroundStyle(checkIn.status.color)
                    .font(.caption2)
                Text(headerText)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
            if !checkIn.purpose.isEmpty {
                Text(checkIn.purpose)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.primary)
                    .padding(.leading, 18)
            }
            if !checkIn.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(checkIn.notes) { note in
                        GroupRecapNoteBlock(note: note)
                    }
                }
                .padding(.leading, 18)
            }
        }
    }

    private var headerText: String {
        let label = checkIn.status.displayLabel
        if let date = checkIn.date {
            return "\(label) · \(date.formatted(date: .abbreviated, time: .omitted))"
        }
        return label
    }
}

// MARK: - Note Block

struct GroupRecapNoteBlock: View {
    let note: GroupRecapNote

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: note.isPinned ? "pin.fill" : "quote.opening")
                .font(.caption2)
                .foregroundStyle(note.isPinned ? .orange : .secondary)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.body)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.primary)
                if let createdAt = note.createdAt {
                    Text(createdAt, format: .relative(presentation: .named))
                        .font(AppTheme.ScaledFont.captionSmallLight)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

// MARK: - Flag Pill

struct GroupRecapFlagPill: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(AppTheme.ScaledFont.captionSmallSemibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.18)))
            .foregroundStyle(color)
    }
}

// MARK: - Detail Labeled Block

struct DetailLabeledBlock: View {
    let label: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
            Text(text)
                .font(AppTheme.ScaledFont.body)
        }
    }
}
