// WeekDayColumn+Time.swift
// Start times in a day column (docs/Plans/Plan - Lesson times on cards.md,
// Phase 3): each card's time chip and the picker it opens, the card menu's
// time items, the "Any time" divider inside a half, and where a drop may land
// among cards with a set time.
//
// Inside a half, lessons with a set time come first in clock order and the
// rest follow in the order the guide dragged them (`LessonAssignmentOrdering`,
// which `WeekPlanSection` already sorts every day by). A timed card's time
// decides its place, so a drop and its insertion bar only ever land among the
// untimed cards: the bar never draws between two timed ones (decision 6).

import SwiftUI
import CoreData

extension WeekDayColumn {

    /// What the list and the drop need to know about one card.
    struct CardPlace: Equatable {
        let half: DayPeriod
        var isTimed = false
    }

    /// What is printed above one card of the day's list.
    struct ListMarks: Equatable {
        /// "Morning" or "Afternoon", above the first card of each half.
        var halfLabel: DayPeriod?
        /// The thin "Any time" divider, above the first untimed card of a half
        /// that also has timed ones.
        var anyTimeDivider = false
    }

    // MARK: - Reading the day

    func isTimed(_ assignment: CDLessonAssignment) -> Bool {
        DayHalfPlanner.isSetTime(assignment.scheduledFor, using: calendar)
    }

    func place(of assignment: CDLessonAssignment) -> CardPlace {
        CardPlace(half: half(of: assignment) ?? .morning, isTimed: isTimed(assignment))
    }

    /// The day's lessons that share a start time with another (decision 7).
    var sameTimeClashIDs: Set<UUID> {
        DayBalanceService.sameTimeClashes(for: scheduledLessonsForDay, using: calendar)
    }

    // MARK: - The list's labels

    /// The labels above each card of a day already in the shared order.
    static func listMarks(for places: [CardPlace]) -> [ListMarks] {
        places.indices.map { index in
            let here = places[index]
            guard index > 0 else { return ListMarks(halfLabel: here.half) }
            let above = places[index - 1]
            if above.half != here.half { return ListMarks(halfLabel: here.half) }
            return ListMarks(anyTimeDivider: above.isTimed && !here.isTimed)
        }
    }

    /// The thin line between a half's timed cards and the rest. Print only,
    /// like the half labels: the list stays one run and one drop zone.
    var anyTimeDivider: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                .frame(height: 1)
            Text("Any time")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.tertiary)
                .fixedSize()
            Rectangle()
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                .frame(height: 1)
        }
        .padding(.horizontal, 4)
    }

    // MARK: - Where a drop lands

    /// `index` (a drop's place among the day's cards, top to bottom) moved past
    /// any timed cards it would land in front of in the same half, so it is
    /// always a place among the untimed cards.
    ///
    /// Only within a half: at the seam between the halves the drop stays where
    /// it is, under the last morning card, because that is the morning it was
    /// aimed at — pushing it past the afternoon's timed cards would make it an
    /// afternoon lesson.
    static func untimedInsertionIndex(_ index: Int, among cards: [CardPlace]) -> Int {
        var landing = max(0, min(index, cards.count))
        while landing < cards.count, cards[landing].isTimed,
              landing == 0 || cards[landing - 1].half == cards[landing].half {
            landing += 1
        }
        return landing
    }

    // MARK: - The chip and its picker

    func timeChip(
        for assignment: CDLessonAssignment, sameTimeClashes: Set<UUID>
    ) -> PresentationPlannerCard.TimeChip {
        let id = assignment.id
        return PresentationPlannerCard.TimeChip(
            time: assignment.setTimeMinute(using: calendar).map(LessonClockTime.init(minutesAfterMidnight:)),
            isClash: id.map(sameTimeClashes.contains) ?? false,
            isPickerShown: Binding(
                get: { id != nil && timePickerID == id },
                set: { shown in
                    if shown {
                        timePickerID = id
                    } else if timePickerID == id {
                        timePickerID = nil
                    }
                }
            ),
            picker: { timePicker(for: assignment) }
        )
    }

    /// The chip as a drag preview draws it: the same look, nothing to press.
    func plainTimeChip(
        for assignment: CDLessonAssignment, sameTimeClashes: Set<UUID>
    ) -> PresentationPlannerCard.TimeChip {
        PresentationPlannerCard.TimeChip(
            time: assignment.setTimeMinute(using: calendar).map(LessonClockTime.init(minutesAfterMidnight:)),
            isClash: assignment.id.map(sameTimeClashes.contains) ?? false
        )
    }

    func timePicker(for assignment: CDLessonAssignment) -> LessonTimePicker {
        let lesson = lessons.first { $0.id == assignment.resolvedLessonID }
        return LessonTimePicker(
            lessonTitle: LessonFormatter.lessonName(lesson?.name, missing: LessonFormatter.untitledLesson),
            current: assignment.setTimeMinute(using: calendar).map(LessonClockTime.init(minutesAfterMidnight:)),
            takenMinutes: takenMinutes(besides: assignment),
            startingHalf: half(of: assignment) ?? .morning,
            set: { hour, minute in setTime(of: assignment, hour: hour, minute: minute) },
            remove: { removeTime(of: assignment) }
        )
    }

    /// The start times the day's other lessons already have, for the picker's dots.
    func takenMinutes(besides assignment: CDLessonAssignment) -> Set<Int> {
        Set(scheduledLessons.compactMap { other in
            other.objectID == assignment.objectID ? nil : other.setTimeMinute(using: calendar)
        })
    }

    /// Sets the time through the planner's rules; a time in the other half
    /// moves the lesson there, since the half is read off the clock.
    func setTime(of assignment: CDLessonAssignment, hour: Int, minute: Int) {
        guard assignment.managedObjectContext != nil else { return }
        adaptiveWithAnimation(Self.balanceAnimation) {
            assignment.setTime(hour: hour, minute: minute, using: AppCalendar.shared)
        }
        saveTime(of: assignment, reason: "Set a lesson's start time")
    }

    /// Takes the time off: the lesson stays in its half, last of the untimed.
    func removeTime(of assignment: CDLessonAssignment) {
        guard assignment.managedObjectContext != nil else { return }
        adaptiveWithAnimation(Self.balanceAnimation) {
            assignment.removeTime(using: AppCalendar.shared)
        }
        saveTime(of: assignment, reason: "Remove a lesson's start time")
    }

    /// Saves the change. A failed save raises the shared alert and puts the
    /// lesson back as the store has it, as a failed drop does.
    private func saveTime(of assignment: CDLessonAssignment, reason: String) {
        guard !dependencies.saveCoordinator.save(viewContext, reason: reason),
              assignment.managedObjectContext != nil else { return }
        viewContext.refresh(assignment, mergeChanges: false)
    }

    // MARK: - The card's menu

    /// A card menu's time items, decided apart from the drawing so the tests
    /// read the same list the menu shows.
    enum TimeMenuItem: Equatable, CaseIterable {
        case set, change, remove

        var title: String {
            switch self {
            case .set: "Set Time…"
            case .change: "Change Time…"
            case .remove: "Remove Time"
            }
        }

        var systemImage: String {
            switch self {
            case .set, .change: "clock"
            case .remove: "clock.badge.xmark"
            }
        }
    }

    static func timeMenuItems(isTimed: Bool) -> [TimeMenuItem] {
        isTimed ? [.change, .remove] : [.set]
    }

    @ViewBuilder
    func timeMenu(for assignment: CDLessonAssignment) -> some View {
        ForEach(Self.timeMenuItems(isTimed: isTimed(assignment)), id: \.self) { item in
            Button(item.title, systemImage: item.systemImage) {
                switch item {
                case .set, .change:
                    // After the menu has closed, so the popover has a card to
                    // anchor to rather than a menu on its way out.
                    let id = assignment.id
                    Task { @MainActor in timePickerID = id }
                case .remove:
                    removeTime(of: assignment)
                }
            }
        }
    }
}
