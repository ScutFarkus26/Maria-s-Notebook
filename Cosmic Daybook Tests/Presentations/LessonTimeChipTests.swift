import CoreData
import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

/// The time chip on the Scheduled cards (docs/Plans/Plan - Lesson times on
/// cards.md, Phase 3): the order and the "Any time" divider inside each half,
/// the chip's three looks and the day's clash badge, the card menu's time
/// items, where a drop lands among timed cards, the card's spoken label, and
/// pictures of a day's list.
@Suite("Lesson time chip")
@MainActor
struct LessonTimeChipTests {

    private typealias Place = WeekDayColumn.CardPlace
    private typealias Marks = WeekDayColumn.ListMarks

    var calendar: Calendar { AppCalendar.shared }

    /// Wednesday 16 September 2026, a school day.
    var wednesday: Date {
        calendar.startOfDay(for: calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 12))!)
    }

    func slot(_ rank: Int, _ period: DayPeriod) -> Date {
        DayHalfPlanner.slot(rank, in: period, on: wednesday, using: calendar)
    }

    func at(_ hour: Int, _ minute: Int) -> Date {
        DayHalfPlanner.settingTime(hour: hour, minute: minute, on: wednesday, using: calendar)
    }

    // MARK: - Order and the divider

    @Test("Each half gets its label, and a divider between its timed and untimed cards")
    func marksForMixedHalves() {
        let places = [
            Place(half: .morning, isTimed: true),
            Place(half: .morning, isTimed: true),
            Place(half: .morning),
            Place(half: .morning),
            Place(half: .afternoon, isTimed: true),
            Place(half: .afternoon)
        ]
        #expect(WeekDayColumn.listMarks(for: places) == [
            Marks(halfLabel: .morning),
            Marks(),
            Marks(anyTimeDivider: true),
            Marks(),
            Marks(halfLabel: .afternoon),
            Marks(anyTimeDivider: true)
        ])
    }

    @Test("A half with only one kind of card has no divider")
    func noDividerForOneKind() {
        let places = [
            Place(half: .morning, isTimed: true),
            Place(half: .morning, isTimed: true),
            Place(half: .afternoon),
            Place(half: .afternoon)
        ]
        let marks = WeekDayColumn.listMarks(for: places)
        #expect(marks.filter(\.anyTimeDivider).isEmpty)
        #expect(marks.compactMap(\.halfLabel) == [.morning, .afternoon])
        #expect(WeekDayColumn.listMarks(for: []).isEmpty)
    }

    @Test("A day's lessons in the shared order: timed first in each half, then the hand order")
    func sharedOrderFeedsTheMarks() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let late = planned(at: slot(1, .morning), in: context)
        let early = planned(at: slot(0, .morning), in: context)
        let tenThirty = planned(at: at(10, 30), in: context)
        let nine = planned(at: at(9, 0), in: context)
        let afternoonSlot = planned(at: slot(0, .afternoon), in: context)
        let oneFifteen = planned(at: at(13, 15), in: context)

        let ordered = LessonAssignmentOrdering.sorted(
            [late, early, tenThirty, nine, afternoonSlot, oneFifteen], using: calendar
        )
        #expect(ordered.map(\.objectID) == [nine, tenThirty, early, late, oneFifteen, afternoonSlot].map(\.objectID))

        let places = ordered.map { item in
            Place(
                half: DayPeriod(scheduledFor: item.scheduledFor!, using: calendar),
                isTimed: DayHalfPlanner.isSetTime(item.scheduledFor, using: calendar)
            )
        }
        let marks = WeekDayColumn.listMarks(for: places)
        // Exactly 9:00 is a set time (the marker), not the first slot.
        #expect(places[0].isTimed)
        #expect(marks.map(\.anyTimeDivider) == [false, false, true, false, false, true])
    }

    // MARK: - Where a drop lands

    @Test("A drop never lands between two timed cards, nor above them in their half")
    func dropLandsAmongUntimedCards() {
        let day = [
            Place(half: .morning, isTimed: true),
            Place(half: .morning, isTimed: true),
            Place(half: .morning),
            Place(half: .afternoon, isTimed: true),
            Place(half: .afternoon)
        ]
        // Above the first card, and between the two timed ones: after them.
        #expect(WeekDayColumn.untimedInsertionIndex(0, among: day) == 2)
        #expect(WeekDayColumn.untimedInsertionIndex(1, among: day) == 2)
        // Among the untimed: where it was aimed.
        #expect(WeekDayColumn.untimedInsertionIndex(2, among: day) == 2)
        // The seam stays the end of the morning rather than becoming the afternoon.
        #expect(WeekDayColumn.untimedInsertionIndex(3, among: day) == 3)
        // Past the afternoon's timed card, and the end.
        #expect(WeekDayColumn.untimedInsertionIndex(4, among: day) == 4)
        #expect(WeekDayColumn.untimedInsertionIndex(5, among: day) == 5)
        #expect(WeekDayColumn.untimedInsertionIndex(9, among: day) == 5)
    }

    @Test("A morning of only timed cards: a drop goes to its end, before the Afternoon label")
    func dropAfterATimedMorning() {
        let day = [
            Place(half: .morning, isTimed: true),
            Place(half: .morning, isTimed: true),
            Place(half: .afternoon)
        ]
        #expect(WeekDayColumn.untimedInsertionIndex(1, among: day) == 2)
        // And the bar is drawn under the last morning card, above the label.
        let cards = [
            WeekDayColumn.PlacedCard(frame: CGRect(x: 0, y: 0, width: 100, height: 40), half: .morning, isTimed: true),
            WeekDayColumn.PlacedCard(frame: CGRect(x: 0, y: 46, width: 100, height: 40), half: .morning, isTimed: true),
            WeekDayColumn.PlacedCard(frame: CGRect(x: 0, y: 110, width: 100, height: 40), half: .afternoon)
        ]
        #expect(cards.map(\.place) == day)
        #expect(WeekDayColumn.insertionBarY(at: 2, among: cards) == 89)
        // On an afternoon-only day the drop goes past its timed run too.
        let afternoon = [Place(half: .afternoon, isTimed: true), Place(half: .afternoon)]
        #expect(WeekDayColumn.untimedInsertionIndex(0, among: afternoon) == 1)
    }

    @Test("Dropped between two timed lessons, an untimed one is stored as the bar showed it")
    func dropBetweenTimedStoresTheSame() {
        let first = UUID(), second = UUID(), dropped = UUID(), untimed = UUID()
        let scheduled = [first: at(9, 30), second: at(10, 0), untimed: slot(0, .morning), dropped: slot(2, .afternoon)]
        // Landed between the two timed cards, as the raw index would put it…
        let between = DayHalfPlanner.times(
            for: DayHalfPlanner.placementsAfterDrop(
                ordering: [first, dropped, second, untimed], dropped: [dropped],
                scheduledFor: scheduled, using: calendar
            ),
            on: wednesday, using: calendar, spacingSeconds: 1
        )
        // …and after them, where the bar is drawn.
        let after = DayHalfPlanner.times(
            for: DayHalfPlanner.placementsAfterDrop(
                ordering: [first, second, dropped, untimed], dropped: [dropped],
                scheduledFor: scheduled, using: calendar
            ),
            on: wednesday, using: calendar, spacingSeconds: 1
        )
        #expect(between == after)
        #expect(between[dropped] == slot(0, .morning))
        #expect(between[untimed] == slot(1, .morning))
        #expect(between[first] == at(9, 30))
        #expect(between[second] == at(10, 0))
    }

    // MARK: - Clashes

    @Test("Two lessons at one start time are both amber; the others are not")
    func chipClashState() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let one = planned(at: at(9, 30), in: context)
        let two = planned(at: at(9, 30), in: context)
        let other = planned(at: at(10, 0), in: context)
        let untimed = planned(at: slot(0, .morning), in: context)
        let day = [one, two, other, untimed]

        let clashes = DayBalanceService.sameTimeClashes(for: day, using: calendar)
        #expect(clashes == Set([one, two].compactMap(\.id)))

        let column = column(for: day)
        let styles = day.map {
            PresentationPlannerCard.TimeChipStyle(column.plainTimeChip(for: $0, sameTimeClashes: clashes))
        }
        #expect(styles == [.clash, .clash, .set, .unset])
        // The drag preview's chip has nothing to press.
        #expect(column.plainTimeChip(for: one, sameTimeClashes: clashes).isPickerShown == nil)
    }

    @Test("The badge counts children twice in a half and start times with two lessons; it says how many lessons")
    func badgeCount() {
        let maya = UUID(), noa = UUID()
        let both = WeekDayColumn.dayClashes(
            childClashes: [.morning: [maya], .afternoon: [maya, noa]],
            setMinutes: [570, 570, 600, 780, 780, 780]
        )
        #expect(both == WeekDayColumn.DayClashes(children: 2, sameTimes: 2, sameTimeLessons: 5))
        #expect(both.badgeText == "4 clashes")
        #expect(both.spokenLabel == "2 children booked twice in the same half, "
            + "5 lessons sharing 2 start times. Rearrange this day.")

        let timesOnly = WeekDayColumn.dayClashes(childClashes: [:], setMinutes: [570, 570, 600])
        #expect(timesOnly == WeekDayColumn.DayClashes(children: 0, sameTimes: 1, sameTimeLessons: 2))
        #expect(timesOnly.badgeText == "1 clash")
        // Rearranging never moves a timed lesson, so no "Rearrange" here.
        #expect(timesOnly.spokenLabel == "2 lessons at the same time.")

        // Three at one start time are one clash, and VoiceOver says three.
        let three = WeekDayColumn.dayClashes(childClashes: [:], setMinutes: [600, 600, 600])
        #expect(three.badgeText == "1 clash")
        #expect(three.spokenLabel == "3 lessons at the same time.")

        let childOnly = WeekDayColumn.dayClashes(childClashes: [.morning: [maya]], setMinutes: [570, 600])
        #expect(childOnly.spokenLabel == "1 child booked twice in the same half. Rearrange this day.")
        #expect(WeekDayColumn.dayClashes(childClashes: [:], setMinutes: [570, 600]).total == 0)
    }

    // MARK: - The menu

    @Test("A card's menu offers Set Time, or Change Time and Remove Time")
    func menuItems() {
        #expect(WeekDayColumn.timeMenuItems(isTimed: false).map(\.title) == ["Set Time…"])
        #expect(WeekDayColumn.timeMenuItems(isTimed: true).map(\.title) == ["Change Time…", "Remove Time"])
    }

    @Test("Remove Time keeps the lesson in its half, after the hand-ordered ones")
    func removeTimeFromTheMenu() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let timed = planned(at: at(13, 30), in: context)
        timed.removeTime()
        #expect(timed.scheduledFor == slot(DayHalfPlanner.lastSlotRank, .afternoon))
        #expect(WeekDayColumn.timeMenuItems(isTimed: DayHalfPlanner.isSetTime(timed.scheduledFor)).map(\.title)
            == ["Set Time…"])
    }

    // MARK: - VoiceOver

    @Test("The card's spoken label gains the time, and a same-time clash")
    func spokenLabel() {
        let time = LessonClockTime(hour: 10, minute: 0)
        let plain = PresentationPlannerCard.spokenLabel(
            lessonName: "Commutative Law", studentNames: ["Ora P", "Avital P"], period: .morning,
            timeChip: nil, showFirstLine: nil
        )
        #expect(plain == "Commutative Law, Ora P, Avital P, Morning")

        let unset = PresentationPlannerCard.spokenLabel(
            lessonName: "Commutative Law", studentNames: ["Ora P"], period: .morning,
            timeChip: .init(time: nil), showFirstLine: nil
        )
        #expect(unset == "Commutative Law, Ora P, Morning")

        let timed = PresentationPlannerCard.spokenLabel(
            lessonName: "Commutative Law", studentNames: ["Ora P"], period: .morning,
            timeChip: .init(time: time), showFirstLine: nil
        )
        #expect(timed == "Commutative Law, Ora P, Morning, " + LessonTimeText.spokenPhrase(time))

        let clash = PresentationPlannerCard.spokenLabel(
            lessonName: "Commutative Law", studentNames: [], period: .morning,
            timeChip: .init(time: time, isClash: true), showFirstLine: "1 work to check first"
        )
        #expect(clash == "Commutative Law, Morning, " + LessonTimeText.spokenPhrase(time)
            + ", another lesson at the same time, 1 work to check first")
    }
}
