// ScheduleItemViews.swift
// One item of a Schedules lane, drawn the same in the Day view's lanes, the
// iPhone's list and the Week view: a block, a turn (outlined in the room's
// color inside the person's lane), one of the guide's lessons at its time,
// or a half's numbered list. A block changed for the day has a dashed outline.

import SwiftUI

/// What every item view needs to word itself.
struct ScheduleItemStyle {
    let lanesByID: [UUID: TimetableLaneSnapshot]
    /// Short names by upper-cased student ID.
    let names: [String: String]
    let isToday: Bool

    func name(_ id: String) -> String? { names[id.uppercased()] }

    func color(of laneID: UUID) -> Color {
        lanesByID[laneID].map(ScheduleLaneColor.color(of:)) ?? .gray
    }
}

/// The edits an item and a lane header offer, each for a given day.
struct ScheduleActions {
    var edit: (ScheduleDay.Block, Date) -> Void
    var cancelThisDay: (ScheduleDay.Block, Date) -> Void
    var undoChange: (ScheduleDay.Block, Date) -> Void
    var delete: (ScheduleDay.Block, Date) -> Void
    var setOut: (UUID, Bool, Date) -> Void
    var addToDay: (UUID?, Date) -> Void
}

struct ScheduleItemView: View {
    let item: ScheduleDay.Item
    let lane: TimetableLaneSnapshot
    let style: ScheduleItemStyle
    var isHighlighted = false
    /// Drawn short in the Day view's lanes: a block's title and time on one line.
    var isCompact = false

    var body: some View {
        content
            .overlay {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small)
                        .stroke(Color.accentColor, lineWidth: 3)
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .block(let block):
            ScheduleBlockCard(
                block: block, color: style.color(of: block.laneID), title: blockTitle(block), style: style,
                isCompact: isCompact
            )
        case .turn(let block):
            ScheduleBlockCard(
                block: block, color: style.color(of: block.laneID),
                title: ScheduleText.turnTitle(
                    room: style.lanesByID[block.laneID]?.name ?? "", title: block.values.title
                ),
                style: style, isTurn: true, isCompact: isCompact
            )
        case .lesson(let lesson):
            ScheduleLessonRow(lesson: lesson, color: style.color(of: lane.id), style: style)
        case .halfList(let half, let lessons):
            ScheduleHalfListCard(half: half, lessons: lessons, color: style.color(of: lane.id), style: style)
        }
    }

    private func blockTitle(_ block: ScheduleDay.Block) -> String {
        let title = block.values.title.trimmed()
        return title.isEmpty ? "Untitled" : title
    }
}

// MARK: - A block or a turn

struct ScheduleBlockCard: View {
    let block: ScheduleDay.Block
    /// The block's lane's color (the room's, for a turn).
    let color: Color
    let title: String
    let style: ScheduleItemStyle
    var isTurn = false
    var isCompact = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small, style: .continuous)
    }

    var body: some View {
        Group {
            if isCompact { compactContent } else { fullContent }
        }
        .padding(.vertical, isCompact ? 3 : 6)
        .padding(.leading, isTurn ? 8 : 10)
        .padding(.trailing, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            isTurn ? Color.primary.opacity(UIConstants.OpacityConstants.whisper) : color.opacity(0.14), in: shape
        )
        .overlay(alignment: .leading) {
            if !isTurn {
                UnevenRoundedRectangle(
                    topLeadingRadius: UIConstants.CornerRadius.small,
                    bottomLeadingRadius: UIConstants.CornerRadius.small
                )
                .fill(color)
                .frame(width: 4)
            }
        }
        .overlay {
            if block.isDayChange {
                shape.stroke(color, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
            } else if isTurn {
                shape.stroke(color, lineWidth: 1.5)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var mark: String? { ScheduleText.dayMark(block, isToday: style.isToday) }

    private var rangeText: some View {
        Text(TimetableDay.rangeText(block.values))
            .font(AppTheme.ScaledFont.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    /// A short block: title, time and mark on one line.
    private var compactContent: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title)
                .font(AppTheme.ScaledFont.bodySemibold)
                .lineLimit(1)
                .layoutPriority(1)
            rangeText
                .fixedSize()
            Spacer(minLength: 0)
            if let mark {
                Text(mark)
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
    }

    private var fullContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(AppTheme.ScaledFont.bodySemibold)
                .lineLimit(2)
            rangeText
            if let mark {
                Text(mark)
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            if !isTurn, let teacher = ScheduleText.teacher(of: block.values, lanes: style.lanesByID) {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill")
                        .imageScale(.small)
                    Text(block.teacherIsOut ? "\(teacher) is out" : teacher)
                        .lineLimit(1)
                }
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(block.teacherIsOut ? .orange : .secondary)
            }
            if let children = ScheduleText.children(block.values.studentIDs, name: style.name) {
                Text(children)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            let note = block.values.note.trimmed()
            if !note.isEmpty {
                Text(note)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
            // The guide's adolescents-only lessons placed in it, in his turn and in the room alike.
            if !block.lessons.isEmpty {
                ScheduleNumberedLessons(lessons: block.lessons, style: style)
                    .padding(.top, 2)
            }
        }
    }
}

// MARK: - The guide's lessons

/// One of the guide's lessons at its set time.
struct ScheduleLessonRow: View {
    let lesson: ScheduleDay.Lesson
    let color: Color
    let style: ScheduleItemStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let minute = lesson.snapshot.minute {
                    Text(TimetableDay.clockText(minute))
                        .font(AppTheme.ScaledFont.captionSemibold.monospacedDigit())
                        .foregroundStyle(color)
                }
                Text(ScheduleText.lessonTitle(lesson))
                    .font(AppTheme.ScaledFont.body)
                    .lineLimit(1)
                if let children = ScheduleText.children(lesson.snapshot.studentIDs, name: style.name) {
                    Text(children)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if let note = lesson.note {
                Label(note, systemImage: "exclamationmark.circle")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color.opacity(0.08), in: Capsule())
        .accessibilityElement(children: .combine)
    }
}

/// A half's lessons, numbered in the guide's order, as one band.
struct ScheduleHalfListCard: View {
    let half: ScheduleDayHalf
    let lessons: [ScheduleDay.Lesson]
    let color: Color
    let style: ScheduleItemStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(ScheduleText.halfListTitle(half))
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(color)
            ScheduleNumberedLessons(lessons: lessons, style: style)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            color.opacity(0.08),
            in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.small, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }
}

/// "1. Long Division · Maya S, Eli B", one line each, with a lesson's note under it.
struct ScheduleNumberedLessons: View {
    let lessons: [ScheduleDay.Lesson]
    let style: ScheduleItemStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(lessons.enumerated()), id: \.element.id) { index, lesson in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(index + 1).")
                            .font(AppTheme.ScaledFont.captionSemibold.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(ScheduleText.lessonTitle(lesson))
                            .font(AppTheme.ScaledFont.caption.weight(.medium))
                            .lineLimit(1)
                        if let children = ScheduleText.children(lesson.snapshot.studentIDs, name: style.name) {
                            Text("· \(children)")
                                .font(AppTheme.ScaledFont.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    if let note = lesson.note {
                        Text(note)
                            .font(AppTheme.ScaledFont.captionSmall)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

// MARK: - Menus

/// The menu a block offers wherever it shows: edit it, cancel it for the
/// day, take back the day's change, delete it.
struct ScheduleBlockMenu: ViewModifier {
    let block: ScheduleDay.Block?
    let day: Date
    let actions: ScheduleActions

    func body(content: Content) -> some View {
        if let block {
            content
                .contentShape(Rectangle())
                .onTapGesture { actions.edit(block, day) }
                .contextMenu {
                    Button("Edit…", systemImage: "pencil") { actions.edit(block, day) }
                    if block.isChanged {
                        Button("Undo This Day’s Change", systemImage: "arrow.uturn.backward") {
                            actions.undoChange(block, day)
                        }
                    }
                    if !block.isOneOff {
                        Button("Cancel This Day", systemImage: "calendar.badge.minus") {
                            actions.cancelThisDay(block, day)
                        }
                    }
                    Divider()
                    Button("Delete…", systemImage: "trash", role: .destructive) { actions.delete(block, day) }
                }
        } else {
            content
        }
    }
}

extension View {
    func scheduleBlockMenu(_ block: ScheduleDay.Block?, day: Date, actions: ScheduleActions) -> some View {
        modifier(ScheduleBlockMenu(block: block, day: day, actions: actions))
    }
}
