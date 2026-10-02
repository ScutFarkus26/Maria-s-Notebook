// TodayGoneQuietRows.swift
// Gone quiet's rows: open work nobody has touched in a while.
//
// A row leads with the work's title, then the children as short-name chips
// (absent ones struck through, as on the lesson rows), with the age chip at
// the trailing edge — "19d quiet", orange from 18 days. Below that, the
// work's open linked todos ("3 todos · Sep 18", red when overdue) and a
// Schedule check-in button, which opens the work-check day picker on the
// next school day. A group or flexible lesson's children share one row; a
// flexible row still expands to each child.

import SwiftUI

// MARK: - One child's work

struct FollowUpWorkListRow: View {
    let item: FollowUpWorkItem
    let title: String
    let children: [TodayStudentChips.Chip]
    var linkedTodos: TodayLinkedTodos.WorkTodos?
    /// Where the Schedule check-in picker opens: the next school day.
    let checkInDay: Date
    var onTap: () -> Void
    var onSchedule: (Date) -> Void

    private var accessibilityLabelText: String {
        var label = "\(title), \(TodayGoneQuiet.ageText(days: item.daysSinceTouch))"
        if !children.isEmpty {
            label += ", for \(TodayGoneQuietRowText.names(children))"
        }
        if let linkedTodos {
            label += ", \(linkedTodos.summary)\(linkedTodos.isOverdue ? ", overdue" : "")"
        }
        return label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button(action: onTap) {
                    TodayGoneQuietRowHeading(title: title, children: children)
                }
                .buttonStyle(.subtleRow)
                .accessibilityLabel(accessibilityLabelText)
                .accessibilityHint("Views work details")
                TodayQuietAgeChip(days: item.daysSinceTouch)
            }
            TodayGoneQuietRowFooter(
                linkedTodos: linkedTodos, count: 1, checkInDay: checkInDay, onSchedule: onSchedule
            )
        }
    }
}

// MARK: - A lesson's children together

struct GroupedFollowUpWorkListRow: View {
    let items: [FollowUpWorkItem]
    let title: String
    /// One chip per item, in the items' order.
    let children: [TodayStudentChips.Chip]
    var linkedTodos: TodayLinkedTodos.WorkTodos?
    let isFlexible: Bool
    let checkInDay: Date
    var onTap: (UUID) -> Void
    /// Schedules every child on the row for the picked day.
    var onSchedule: (Date) -> Void

    @State private var isExpanded: Bool = false

    private var maxDaysSinceTouch: Int {
        items.map(\.daysSinceTouch).max() ?? 0
    }

    private var accessibilityLabelText: String {
        var label = "\(title), \(items.count) children, \(TodayGoneQuiet.ageText(days: maxDaysSinceTouch))"
        if !children.isEmpty {
            label += ", for \(TodayGoneQuietRowText.names(children))"
        }
        if let linkedTodos {
            label += ", \(linkedTodos.summary)\(linkedTodos.isOverdue ? ", overdue" : "")"
        }
        return label
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button {
                    if isFlexible {
                        adaptiveWithAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            isExpanded.toggle()
                        }
                    } else if let workID = items.first?.work.id {
                        onTap(workID)
                    }
                } label: {
                    TodayGoneQuietRowHeading(title: title, children: children)
                }
                .buttonStyle(.subtleRow)
                .accessibilityLabel(accessibilityLabelText)
                .accessibilityHint(isFlexible ? "Expands individual students" : "Views the group's work")
                if isFlexible {
                    Image(systemName: isExpanded ? SFSymbol.Navigation.chevronUp : SFSymbol.Navigation.chevronDown)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                TodayQuietAgeChip(days: maxDaysSinceTouch)
            }
            if isFlexible && isExpanded {
                expandedChildren
            }
            TodayGoneQuietRowFooter(
                linkedTodos: linkedTodos, count: items.count, checkInDay: checkInDay, onSchedule: onSchedule
            )
        }
    }

    private var expandedChildren: some View {
        VStack(spacing: 4) {
            ForEach(Array(zip(items, children)), id: \.0.id) { item, child in
                Button {
                    if let workID = item.work.id { onTap(workID) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: SFSymbol.People.personFill)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(child.name)
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(child.isAbsent ? .tertiary : .primary)
                            .strikethrough(child.isAbsent)
                        Spacer()
                        Text(TodayGoneQuiet.ageText(days: item.daysSinceTouch))
                            .font(AppTheme.ScaledFont.caption)
                            .foregroundStyle(.quaternary)
                    }
                    .padding(.leading, 12)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.subtleRow)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - Pieces

/// The work's title, then its children as chips.
private struct TodayGoneQuietRowHeading: View {
    let title: String
    let children: [TodayStudentChips.Chip]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTheme.ScaledFont.calloutSemibold)
                .foregroundStyle(.primary)
                .lineLimit(2)
            if !children.isEmpty {
                TodayStudentChips(chips: children)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The linked todos on the left, Schedule check-in on the right.
private struct TodayGoneQuietRowFooter: View {
    let linkedTodos: TodayLinkedTodos.WorkTodos?
    let count: Int
    let checkInDay: Date
    let onSchedule: (Date) -> Void

    @State private var isPickingDay = false

    var body: some View {
        HStack(spacing: 8) {
            if let linkedTodos {
                TodayLinkedTodosLabel(todos: linkedTodos)
            }
            Spacer(minLength: 0)
            Button("Schedule check-in") { isPickingDay = true }
                .buttonStyle(.borderless)
                .font(AppTheme.ScaledFont.caption)
                .help(
                    count == 1
                        ? "Puts this work on a day to be checked"
                        : "Puts these children's work on a day to be checked"
                )
        }
        .modifier(DayPickerPresentation(
            isPresented: $isPickingDay, count: count, initialDay: checkInDay, onPick: onSchedule
        ))
    }
}

/// "19d quiet" — orange from `TodayGoneQuiet.longQuietDays`.
struct TodayQuietAgeChip: View {
    let days: Int

    private var color: Color {
        TodayGoneQuiet.isLongQuiet(days: days) ? .orange : .secondary
    }

    var body: some View {
        Text(TodayGoneQuiet.ageText(days: days))
            .font(AppTheme.ScaledFont.captionSmallSemibold)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .capsuleFill(color.opacity(UIConstants.OpacityConstants.subtle))
            .fixedSize()
            .accessibilityHidden(true)
    }
}

/// "3 todos · Sep 18" — red when the soonest is overdue.
struct TodayLinkedTodosLabel: View {
    let todos: TodayLinkedTodos.WorkTodos

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: SFSymbol.List.checklist)
                .font(.system(size: 10))
            Text(todos.summary)
                .font(AppTheme.ScaledFont.caption)
        }
        .foregroundStyle(todos.isOverdue ? Color.red : Color.secondary)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(todos.isOverdue ? "\(todos.summary), overdue" : todos.summary)
    }
}

/// Spoken names for a row's chips, absent ones said so.
private enum TodayGoneQuietRowText {
    static func names(_ children: [TodayStudentChips.Chip]) -> String {
        children.map { $0.isAbsent ? "\($0.name), absent" : $0.name }.joined(separator: ", ")
    }
}
