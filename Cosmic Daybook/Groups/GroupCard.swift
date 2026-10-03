//
//  GroupCard.swift
//  Cosmic Daybook
//
//  One lesson the ready queue proposes, as a card on the Groups page: who is
//  ready (green, with how long each has waited), who a practice gate still
//  holds (orange, with the reason), who could catch up and join (dashed),
//  who is waiting on a confirmation, and whoever already has it planned.
//  The breadcrumb opens the sub-area's ladder; Plan opens the schedule sheet
//  with the ready children selected.
//

import SwiftUI

struct GroupCard: View {
    let group: LessonGroup
    let palette: StudentAgePalette
    let onPlan: () -> Void
    let onConfirm: (LessonGroup.Unconfirmed) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            VStack(alignment: .leading, spacing: 6) {
                ForEach(group.ready) { member in
                    GroupMemberRow(member: member, palette: palette)
                }
                ForEach(group.almost) { member in
                    GroupMemberRow(member: member, palette: palette)
                }
                ForEach(group.catchUp) { ghost in
                    catchUpRow(ghost)
                }
                ForEach(group.unconfirmed) { entry in
                    unconfirmedRow(entry)
                }
            }
            ForEach(group.plannedWith, id: \.self) { plan in
                plannedRow(plan)
            }
            planButton
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(group.lessonName)
                    .font(.headline)
                Spacer(minLength: 8)
                Text(group.stepLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Step \(group.stepLabel)")
            }
            GroupBreadcrumb(area: group.area, sequence: group.sequence)
        }
    }

    // MARK: - Rows

    private func catchUpRow(_ ghost: LessonGroup.CatchUp) -> some View {
        HStack(spacing: 6) {
            Text(ghost.child.name)
                .font(.subheadline)
            Text("could join after \(ghost.afterLessonName)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.secondary, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    private func unconfirmedRow(_ entry: LessonGroup.Unconfirmed) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.child.name)
                    .font(.subheadline)
                Text("Had the previous lesson; not confirmed yet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button("Confirm") { onConfirm(entry) }
                .buttonStyle(.bordered)
                .controlSize(.small)
                #if os(iOS)
                .frame(minHeight: 44)
                #endif
                .accessibilityLabel("Confirm \(entry.child.name)")
        }
    }

    private func plannedRow(_ plan: LessonGroup.Planned) -> some View {
        Label {
            Text(plannedText(plan))
                .font(.caption)
        } icon: {
            Image(systemName: plan.isYearPlan ? "calendar" : "calendar.badge.checkmark")
        }
        .foregroundStyle(Color.accentColor)
    }

    private func plannedText(_ plan: LessonGroup.Planned) -> String {
        let names = plan.children.map(\.name).joined(separator: ", ")
        if plan.isYearPlan { return "On the year plan for \(names)" }
        guard let date = plan.date else { return "Planned with \(names)" }
        return "Planned with \(names) · \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private var planButton: some View {
        Button(action: onPlan) {
            Text("Plan")
                .frame(maxWidth: .infinity)
                #if os(iOS)
                .frame(minHeight: 32)
                #endif
        }
        .buttonStyle(.borderedProminent)
        .disabled(group.ready.isEmpty)
        .accessibilityLabel("Plan \(group.lessonName)")
    }
}

/// "Area · Sequence", pushing the sub-area's ladder.
struct GroupBreadcrumb: View {
    let area: String
    let sequence: String

    var body: some View {
        NavigationLink(value: SequenceLadderRoute(area: area, sequence: sequence)) {
            HStack(spacing: 3) {
                Text("\(area) · \(sequence)")
                Image(systemName: "chevron.right")
                    .imageScale(.small)
            }
            .font(.caption)
            .foregroundStyle(Color.accentColor)
            #if os(iOS)
            .frame(minHeight: 44, alignment: .leading)
            #endif
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows every child's place in \(sequence)")
    }
}

/// A ready child (green) or one the practice gate holds (orange, with the
/// reason), and how long she has waited since the lesson that made her ready.
struct GroupMemberRow: View {
    let member: LessonGroup.Member
    let palette: StudentAgePalette

    private var isReady: Bool { member.reason == nil }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(isReady ? AppColors.success : AppColors.warning)
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(member.child.name)
                    .font(.subheadline)
                if let reason = member.reason {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let days = member.waitSchoolDays {
                // The Lesson Age overdue color, as the ladder shows it; orange
                // already means "practice not done" on this row.
                Text(days == 1 ? "1 day" : "\(days) days")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.status(forDays: days) == .overdue ? palette.overdue : .secondary)
                    .accessibilityLabel("Waiting \(days) school days")
            }
        }
        .accessibilityElement(children: .combine)
    }
}
