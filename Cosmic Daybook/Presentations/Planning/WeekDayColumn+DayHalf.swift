// WeekDayColumn+DayHalf.swift
// Morning and afternoon inside one day column.
//
// The day stays a single ordered list and a single drop zone — splitting it
// into an AM stack and a PM stack would double the targets a drag can miss, for
// a distinction the guide changes with one right-click. So the half is read off
// each card, printed as a "Morning" / "Afternoon" label above the first card of
// each run, and inherited by whatever is dropped beneath a card.

import SwiftUI

extension WeekDayColumn {
    /// The half of the day a card sits in — nil when it carries no schedule at
    /// all, which is only the inbox's case and never this column's.
    func half(of assignment: CDLessonAssignment) -> DayPeriod? {
        assignment.scheduledFor.map { DayPeriod(scheduledFor: $0, using: calendar) }
    }

    /// Drives the right-click AM/PM control. Reading a card with no schedule as
    /// a morning only affects which row the menu ticks; setting is what writes.
    func halfBinding(for assignment: CDLessonAssignment) -> Binding<DayPeriod> {
        Binding(
            get: { half(of: assignment) ?? .morning },
            set: { move(assignment, to: $0) }
        )
    }

    /// Moves one presentation to the other half and renumbers the day around it.
    ///
    /// The whole day is rewritten rather than just this card, because the
    /// numbering is positional: the card joining the end of the afternoon run
    /// needs the offset after the last one there, and the run it left has a gap
    /// in it. Rewriting both runs from zero is cheaper to reason about than
    /// patching either.
    func move(_ assignment: CDLessonAssignment, to period: DayPeriod) {
        guard let movedID = assignment.id, half(of: assignment) != period else { return }
        let ordered = scheduledLessonsForDay
        guard ordered.contains(where: { $0.id == movedID }) else { return }

        let placements = DayHalfPlanner.movingToEndOfHalf(
            movedID,
            to: period,
            in: ordered.compactMap { item in
                item.id.map { DayHalfPlanner.Placement(id: $0, period: half(of: item) ?? .morning) }
            }
        )
        let times = DayHalfPlanner.times(
            for: placements,
            on: day,
            using: calendar,
            spacingSeconds: UIConstants.scheduleSpacingSeconds
        )
        for item in ordered {
            if let id = item.id, let time = times[id] {
                item.setScheduledFor(time, using: AppCalendar.shared)
            }
        }
        viewContext.safeSave()
    }

    /// The half the drop in progress will land in, so the insertion bar can say
    /// so before the guide lets go — otherwise the inheritance rule is a thing
    /// the calendar does silently and the guide discovers afterwards.
    func insertionHalf(at index: Int) -> DayPeriod {
        DayHalfPlanner.inheritedPeriod(
            insertingAt: index,
            into: scheduledLessonsForDay.map { half(of: $0) ?? .morning }
        )
    }

    /// A card's measured frame and the half it is in, for placing the bar.
    struct PlacedCard: Equatable {
        let frame: CGRect
        let half: DayPeriod
    }

    /// Where the insertion bar is drawn for a drop at `index`, given the day's
    /// cards sorted top to bottom.
    ///
    /// Normally just above the card the drop lands in front of. The exception
    /// is the seam between the halves, where the "Afternoon" label sits between
    /// the last morning card and the first afternoon one: a drop there takes
    /// the morning (the half of the card above, see `insertionHalf`), so the
    /// bar goes under the morning card, above the label. Drawn below the label
    /// it would sit in the afternoon band while its tag said AM.
    static func insertionBarY(at index: Int, among cards: [PlacedCard]) -> CGFloat {
        let gap: CGFloat = 3
        guard let last = cards.last else { return 16 }
        guard index < cards.count else { return last.frame.maxY + gap }
        if index > 0, cards[index - 1].half != cards[index].half {
            return cards[index - 1].frame.maxY + gap
        }
        return cards[max(index, 0)].frame.minY - gap
    }

    /// Morning or afternoon, offered as a ticked pair rather than a single
    /// "Move to Afternoon" flip: the menu is also where the guide checks which
    /// half a card is already in.
    @ViewBuilder
    func halfPicker(for assignment: CDLessonAssignment) -> some View {
        Picker("Half of Day", selection: halfBinding(for: assignment)) {
            ForEach(DayPeriod.allCases, id: \.self) { period in
                Text("\(period.label) (\(period.abbreviation))").tag(period)
            }
        }
        .pickerStyle(.inline)
    }
}
