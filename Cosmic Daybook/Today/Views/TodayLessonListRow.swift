// TodayLessonListRow.swift
// A lesson on Today: its title first, then the children as short-name chips,
// with "6 of 7 here" at the trailing edge.
//
// Children attendance marks absent are struck through, gray and labeled
// "absent", and the row offers to move them to tomorrow. The first lesson not
// yet given is the Next card: the agenda draws it highlighted
// (`todayNextHighlight`) and passes `onPresent`, which shows Present (⌘↩).
//
// `TodayStudentChips` is the shared chip row; the Gone quiet work rows
// (phase 4) take the same chips.

import SwiftUI

// MARK: - Student chips

/// Children as short-name chips ("Maya S"), wrapping to as many lines as
/// they need. Absent ones are struck through and labeled.
struct TodayStudentChips: View {
    struct Chip: Identifiable, Equatable {
        let id: UUID
        let name: String
        var isAbsent: Bool = false
    }

    let chips: [Chip]

    var body: some View {
        FlowLayout(spacing: 4) {
            ForEach(chips) { chip in
                TodayStudentChip(name: chip.name, isAbsent: chip.isAbsent)
            }
        }
    }
}

/// One child: "Maya S", or "~~Theo S~~ absent" in gray.
struct TodayStudentChip: View {
    let name: String
    var isAbsent: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Text(name)
                .strikethrough(isAbsent)
            if isAbsent {
                Text("absent")
                    .font(AppTheme.ScaledFont.captionSmall)
            }
        }
        .font(AppTheme.ScaledFont.captionSmallSemibold)
        .foregroundStyle(isAbsent ? .tertiary : .secondary)
        .textSelection(.disabled)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .capsuleFill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
        .fixedSize()
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isAbsent ? "\(name), absent" : name)
    }
}

// MARK: - Lesson row

struct LessonListRow: View {
    let lessonName: String
    let children: [TodayStudentChips.Chip]
    /// "6 of 7 here" (`TodayLessonAttendance.hereText`); ignored once given.
    var hereText: String?
    let isPresented: Bool
    var trailingAccessorySystemName: String?
    var trailingAccessoryLabel: String?
    var onTrailingAccessoryTap: (() -> Void)?
    /// Shown as an inline link when the lesson has absent children.
    var onMoveAbsent: (() -> Void)?
    /// The link's words, naming the next school day ("Move absent to Monday").
    var moveAbsentTitle = "Move absent to tomorrow"
    /// The Next card's Present button; nil on every other row.
    var onPresent: (() -> Void)?
    var presentShortcut: KeyboardShortcut?

    private var accessibilityLabelText: String {
        var label = "Lesson: \(lessonName)"
        let here = children.filter { !$0.isAbsent }.map(\.name)
        let absent = children.filter(\.isAbsent).map(\.name)
        if !here.isEmpty {
            label += ", for \(here.joined(separator: ", "))"
        }
        if !absent.isEmpty {
            label += ", absent: \(absent.joined(separator: ", "))"
        }
        if isPresented {
            label += ", presented"
        } else if let hereText {
            label += ", \(hereText)"
        }
        return label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(lessonName)
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .foregroundStyle(isPresented ? .tertiary : .primary)
                    if !children.isEmpty {
                        TodayStudentChips(chips: children)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(accessibilityLabelText)
                .accessibilityHint("Views lesson details")
                Spacer(minLength: 8)
                trailingStatus
                planButton
            }
            if onMoveAbsent != nil || onPresent != nil {
                actionLine
            }
        }
    }

    @ViewBuilder
    private var trailingStatus: some View {
        if isPresented {
            Text("Done")
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        } else if let hereText {
            Text(hereText)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var planButton: some View {
        if let trailingAccessorySystemName, let onTrailingAccessoryTap {
            Button(action: onTrailingAccessoryTap) {
                Image(systemName: trailingAccessorySystemName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(Color.secondary.opacity(UIConstants.OpacityConstants.medium))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel(trailingAccessoryLabel ?? "Open attachment")
        }
    }

    private var actionLine: some View {
        HStack(spacing: 8) {
            if let onMoveAbsent {
                Button(moveAbsentTitle, action: onMoveAbsent)
                    .buttonStyle(.borderless)
                    .font(AppTheme.ScaledFont.caption)
                    .help("Moves the children who are absent onto this lesson on the next school day; the others stay")
            }
            Spacer(minLength: 0)
            if let onPresent {
                TodayNextButton(title: "Present", shortcut: presentShortcut, action: onPresent)
            }
        }
    }
}
