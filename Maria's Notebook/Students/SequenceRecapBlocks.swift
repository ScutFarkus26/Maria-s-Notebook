// SequenceRecapBlocks.swift
// Per-lesson row + presentation/work/check-in/note blocks shown inside the
// expanded SequenceRecapStudentSection.

import SwiftUI

// MARK: - Per-Lesson Row

struct SequenceRecapLessonRow: View {
    let entry: SequenceRecapLessonEntry
    let areaColor: Color
    let studentID: UUID
    let onUpdateState: (UUID, UUID, LessonPresentationState) -> Void
    let onOpenWork: (UUID) -> Void
    let onCycleWorkStatus: (UUID, WorkStatus) -> Void
    let onAddWork: (UUID, UUID, UUID?) -> Void

    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if isExpandable {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }
            } label: {
                summaryRow
            }
            .buttonStyle(.plain)
            .disabled(!isExpandable)

            if isExpanded && isExpandable {
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
        entry.isCurrentLesson ? areaColor.opacity(0.08) : .clear
    }

    private var hasDetails: Bool {
        !entry.presentations.isEmpty
            || !entry.unattachedWorkItems.isEmpty
            || !entry.directNotes.isEmpty
            || !(entry.perStudentLessonNotes ?? "").isEmpty
    }

    /// Non-current rows are always expandable so the user can reach the status picker
    /// even on lessons with no prior history. The current lesson row keeps its existing
    /// gating — that lesson is edited via the main form's ProficiencyStateRow.
    private var isExpandable: Bool {
        entry.isCurrentLesson ? hasDetails : true
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

            SequenceRecapStateBadge(entry: entry)
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
        let firstPresentation = entry.presentations.first
        let firstPresentationWork = firstPresentation?.workItems.first
        let firstUnattachedWork = entry.unattachedWorkItems.first
        return firstPresentation?.presentedAt
            ?? firstPresentation?.scheduledFor
            ?? firstPresentationWork?.completedAt
            ?? firstPresentationWork?.assignedAt
            ?? firstUnattachedWork?.completedAt
            ?? firstUnattachedWork?.assignedAt
    }

    @ViewBuilder
    private var detailContent: some View {
        if let perStudent = entry.perStudentLessonNotes, !perStudent.isEmpty {
            DetailLabeledBlock(label: "Lesson notes", text: perStudent)
        }
        ForEach(entry.presentations) { presentation in
            SequenceRecapPresentationBlock(
                presentation: presentation,
                lessonID: entry.id,
                studentID: studentID,
                onOpenWork: onOpenWork,
                onCycleWorkStatus: onCycleWorkStatus,
                onAddWork: onAddWork
            )
        }
        if !entry.unattachedWorkItems.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Other work")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                ForEach(entry.unattachedWorkItems) { work in
                    SequenceRecapWorkBlock(
                        work: work,
                        onTap: onOpenWork,
                        onCycleStatus: onCycleWorkStatus
                    )
                }
            }
        }
        if entry.presentations.isEmpty && entry.unattachedWorkItems.isEmpty {
            Button {
                onAddWork(entry.id, studentID, nil)
            } label: {
                Label("Add work", systemImage: "plus.circle")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.tint)
            }
            .buttonStyle(.plain)
        }
        if !entry.directNotes.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.secondary)
                ForEach(entry.directNotes) { note in
                    SequenceRecapNoteBlock(note: note)
                }
            }
        }
        if !entry.isCurrentLesson {
            SequenceRecapStatusPicker(
                currentState: entry.outcomeState ?? .presented
            ) { newState in
                onUpdateState(entry.id, studentID, newState)
            }
            .padding(.top, 4)
        }
    }
}

// MARK: - Status Picker

/// Compact three-pill picker (Presented / Practicing / Mastered) shown inside an
/// expanded sibling-lesson row. Drives the per-student CDLessonPresentation state
/// for any lesson in the sequence — independent of the main edit form.
struct SequenceRecapStatusPicker: View {
    let currentState: LessonPresentationState
    let onSelect: (LessonPresentationState) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Update status")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                pill(state: .presented, title: "Presented", icon: "eye.fill", tint: .blue)
                pill(state: .practicing, title: "Practicing", icon: "arrow.triangle.2.circlepath", tint: .purple)
                pill(state: .proficient, title: "Mastered", icon: "checkmark.seal.fill", tint: .green)
            }
        }
    }

    private func pill(
        state: LessonPresentationState,
        title: String,
        icon: String,
        tint: Color
    ) -> some View {
        Button {
            onSelect(state)
        } label: {
            StatePill(
                title: title,
                systemImage: icon,
                tint: tint,
                active: currentState == state
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - State Badge

struct SequenceRecapStateBadge: View {
    let entry: SequenceRecapLessonEntry

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

struct SequenceRecapPresentationBlock: View {
    let presentation: SequenceRecapPresentation
    let lessonID: UUID
    let studentID: UUID
    let onOpenWork: (UUID) -> Void
    let onCycleWorkStatus: (UUID, WorkStatus) -> Void
    let onAddWork: (UUID, UUID, UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.circle")
                    .foregroundStyle(.secondary)
                Text(headerText)
                    .font(AppTheme.ScaledFont.captionSemibold)
                Spacer(minLength: 0)
                if presentation.needsPractice {
                    SequenceRecapFlagPill(label: "Needs practice", color: .blue)
                }
                if presentation.needsAnotherPresentation {
                    SequenceRecapFlagPill(label: "Re-present", color: .orange)
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
                        SequenceRecapNoteBlock(note: note)
                    }
                }
                .padding(.leading, 22)
            }
            if !presentation.workItems.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(presentation.workItems) { work in
                        SequenceRecapWorkBlock(
                            work: work,
                            onTap: onOpenWork,
                            onCycleStatus: onCycleWorkStatus
                        )
                    }
                }
                .padding(.leading, 22)
            }
            if presentation.state != .draft {
                Button {
                    onAddWork(lessonID, studentID, presentation.id)
                } label: {
                    Label("Add work", systemImage: "plus.circle")
                        .font(AppTheme.ScaledFont.captionSmallSemibold)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
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

struct SequenceRecapWorkBlock: View {
    let work: SequenceRecapWorkItem
    let onTap: (UUID) -> Void
    let onCycleStatus: (UUID, WorkStatus) -> Void

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
                        SequenceRecapNoteBlock(note: note)
                    }
                }
                .padding(.leading, 22)
            }
            if !work.checkIns.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(work.checkIns) { ci in
                        SequenceRecapCheckInBlock(checkIn: ci)
                    }
                }
                .padding(.leading, 22)
            }
        }
        .padding(.vertical, 4)
    }

    private var workHeader: some View {
        HStack(spacing: 6) {
            Button {
                onTap(work.id)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: work.kind?.iconName ?? "doc")
                        .foregroundStyle(work.kind?.color ?? .secondary)
                    Text(work.title.isEmpty ? "Untitled work" : work.title)
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.primary)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            statusButton
            if let outcome = work.completionOutcome {
                outcomePill(outcome: outcome)
            }
        }
    }

    private var statusButton: some View {
        Button {
            onCycleStatus(work.id, nextStatus(after: work.status))
        } label: {
            Text(work.status.displayName)
                .font(AppTheme.ScaledFont.captionSmallSemibold)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(work.status.color.opacity(0.18)))
                .foregroundStyle(work.status.color)
        }
        .buttonStyle(.plain)
    }

    private func nextStatus(after status: WorkStatus) -> WorkStatus {
        switch status {
        case .active: return .review
        case .review: return .complete
        case .complete: return .active
        }
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

struct SequenceRecapCheckInBlock: View {
    let checkIn: SequenceRecapCheckIn

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
                        SequenceRecapNoteBlock(note: note)
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

struct SequenceRecapNoteBlock: View {
    let note: SequenceRecapNote

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

struct SequenceRecapFlagPill: View {
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
