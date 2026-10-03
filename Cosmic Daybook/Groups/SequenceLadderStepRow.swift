//
//  SequenceLadderStepRow.swift
//  Cosmic Daybook
//
//  One step of the sequence ladder: its number on the rail, the lesson, and
//  the children standing on it.
//
//  The tiers use the Groups page's colors: success green is ready, warning
//  orange is practice open (with the reason held), accent blue is planned
//  (with the date), a gray question mark is unconfirmed (with a Confirm
//  button), and a dashed outline is a catch-up ghost, someone who could join
//  after the step below. The wait is colored by the guide's Lesson Age
//  settings only once it passes the overdue threshold.
//

import CoreData
import SwiftUI

struct SequenceLadderStepRow: View {
    let step: SequenceLadder.Step
    let isLast: Bool
    let palette: StudentAgePalette
    /// Children the guide has confirmed from this screen (`confirmKey`), so
    /// the row can say so before the page rebuilds its snapshot.
    let confirmed: Set<String>
    let onConfirm: (SequenceLadder.Rung) -> Void

    @ScaledMetric(relativeTo: .caption) private var badgeSize: CGFloat = 28
    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 22

    #if os(iOS)
    private static let minTapHeight: CGFloat = 44
    #else
    private static let minTapHeight: CGFloat = 28
    #endif

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            rail
            VStack(alignment: .leading, spacing: 8) {
                heading
                ForEach(step.children) { rung in
                    rungRow(rung)
                }
                ForEach(step.catchUp) { ghost in
                    ghostRow(ghost)
                }
            }
            .padding(.bottom, isLast ? 0 : 20)
        }
    }

    // MARK: - Rail and heading

    private var rail: some View {
        VStack(spacing: 4) {
            Text("\(step.position.step)")
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: badgeSize, height: badgeSize)
                .background(Circle().fill(.quaternary))
                .accessibilityHidden(true)
            if !isLast {
                Capsule()
                    .fill(.quaternary)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
            }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(step.position.stepLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(step.position.name)
                .font(.headline)
        }
        .frame(minHeight: badgeSize, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    // MARK: - Children

    private func rungRow(_ rung: SequenceLadder.Rung) -> some View {
        let tint = Self.tint(for: rung.tier)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: Self.symbol(for: rung.tier))
                .foregroundStyle(tint)
                .frame(width: iconWidth)
                .padding(.top, 2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(rung.child.name)
                    .font(.subheadline.weight(.medium))
                Text(label(for: rung))
                    .font(.caption)
                    .foregroundStyle(tint)
                if let reason = rung.reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing(for: rung)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(minHeight: Self.minTapHeight)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.opacity(0.10)))
        .accessibilityElement(children: .contain)
    }

    /// One child on one assignment: classmates given the lesson together share
    /// the assignment, and confirming one must not mark the others.
    static func confirmKey(for rung: SequenceLadder.Rung) -> String? {
        rung.confirmAssignmentID.map { "\($0.uriRepresentation().absoluteString)|\(rung.child.id)" }
    }

    @ViewBuilder
    private func trailing(for rung: SequenceLadder.Rung) -> some View {
        switch rung.tier {
        case .unconfirmed:
            if let key = Self.confirmKey(for: rung) {
                if confirmed.contains(key) {
                    Label("Confirmed", systemImage: "checkmark")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(AppColors.success)
                } else {
                    Button("Confirm") { onConfirm(rung) }
                        .buttonStyle(.bordered)
                        .frame(minHeight: Self.minTapHeight)
                        .accessibilityLabel("Confirm \(rung.child.name)")
                }
            }
        case .ready, .practiceOpen:
            if let days = rung.waitSchoolDays {
                waitText(days)
            }
        case .planned:
            EmptyView()
        }
    }

    private func waitText(_ days: Int) -> some View {
        let overdue = palette.status(forDays: days) == .overdue
        return Text(SequenceLadderStepRow.waitDescription(days))
            .font(.caption.monospacedDigit())
            .foregroundStyle(overdue ? palette.overdue : Color.secondary)
            .multilineTextAlignment(.trailing)
            .padding(.top, 2)
    }

    private func ghostRow(_ ghost: LessonGroup.CatchUp) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.badge.clock")
                .foregroundStyle(.secondary)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text("\(ghost.child.name) could join after \(ghost.afterLessonName)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .frame(minHeight: Self.minTapHeight)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
        .accessibilityElement(children: .combine)
    }

    // MARK: - Wording

    private func label(for rung: SequenceLadder.Rung) -> String {
        switch rung.tier {
        case .ready:
            return "Ready"
        case .practiceOpen:
            return "Practice open"
        case .planned:
            guard let date = rung.plannedDate else { return "Planned, no date yet" }
            return "Planned \(date.formatted(.dateTime.month(.abbreviated).day()))"
        case .unconfirmed:
            if let key = Self.confirmKey(for: rung), confirmed.contains(key) { return "Confirmed" }
            return "Not confirmed yet"
        }
    }

    static func tint(for tier: SequenceLadder.Tier) -> Color {
        switch tier {
        case .ready: AppColors.success
        case .practiceOpen: AppColors.warning
        case .planned: Color.accentColor
        case .unconfirmed: Color.secondary
        }
    }

    private static func symbol(for tier: SequenceLadder.Tier) -> String {
        switch tier {
        case .ready: "checkmark.circle.fill"
        case .practiceOpen: "hourglass.circle.fill"
        case .planned: "calendar.circle.fill"
        case .unconfirmed: "questionmark.circle"
        }
    }

    /// "Waiting 9 school days", "Waiting 1 school day", "Given today".
    static func waitDescription(_ days: Int) -> String {
        switch days {
        case ..<1: "Given today"
        case 1: "Waiting 1 school day"
        default: "Waiting \(days) school days"
        }
    }
}
