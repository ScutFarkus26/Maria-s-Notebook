import Foundation
import SwiftUI
import Testing
@testable import CosmicDaybook

/// The lesson time picker's values and words (docs/Plans/Plan - Lesson times on
/// cards.md, Phase 2): the quick times, which half each is in, the time as text
/// on a 12- and a 24-hour clock, the sheet's status line, and pictures of the
/// picker itself.
@MainActor
struct LessonTimePickerTests {

    private static func minutes(_ times: [(Int, Int)]) -> [Int] { times.map { $0.0 * 60 + $0.1 } }

    /// Text formatters put a narrow no-break space before AM/PM; compare plainly.
    private static func plain(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    nonisolated private static let us = Locale(identifier: "en_US")
    nonisolated private static let british = Locale(identifier: "en_GB")
    /// A US device with the 24-Hour Time switch on.
    nonisolated private static let us24: Locale = {
        var components = Locale.Components(locale: Locale(identifier: "en_US"))
        components.hourCycle = .zeroToTwentyThree
        return Locale(components: components)
    }()

    // MARK: - Quick times

    @Test("Morning is every quarter hour from 8:45 to 11:00, ten buttons")
    func morningQuickTimes() {
        #expect(LessonTimeChoices.morning == Self.minutes([
            (8, 45), (9, 0), (9, 15), (9, 30), (9, 45), (10, 0), (10, 15), (10, 30), (10, 45), (11, 0)
        ]))
        #expect(LessonTimeChoices.quickTimes(for: .morning) == LessonTimeChoices.morning)
    }

    @Test("Afternoon is every quarter hour from 1:00 to 3:15, ten buttons")
    func afternoonQuickTimes() {
        #expect(LessonTimeChoices.afternoon == Self.minutes([
            (13, 0), (13, 15), (13, 30), (13, 45), (14, 0), (14, 15), (14, 30), (14, 45), (15, 0), (15, 15)
        ]))
        #expect(LessonTimeChoices.quickTimes(for: .afternoon) == LessonTimeChoices.afternoon)
    }

    @Test("Each quick time falls in its own half; noon starts the afternoon")
    func halves() {
        for minute in LessonTimeChoices.morning {
            #expect(LessonTimeChoices.half(ofMinute: minute) == .morning)
            #expect(LessonClockTime(minutesAfterMidnight: minute).half == .morning)
        }
        for minute in LessonTimeChoices.afternoon {
            #expect(LessonTimeChoices.half(ofMinute: minute) == .afternoon)
        }
        #expect(LessonClockTime(hour: 11, minute: 59).half == .morning)
        #expect(LessonClockTime(hour: 12, minute: 0).half == .afternoon)
        #expect(LessonClockTime(hour: 0, minute: 0).half == .morning)
    }

    @Test("A clock time keeps its hour and minute, and stays on the clock")
    func clockTime() {
        let time = LessonClockTime(hour: 10, minute: 30)
        #expect(time.minutesAfterMidnight == 630)
        #expect(LessonClockTime(minutesAfterMidnight: 630) == time)
        #expect(LessonClockTime(hour: 25, minute: 70) == LessonClockTime(hour: 23, minute: 59))
        #expect(LessonClockTime(hour: 9, minute: 0) < LessonClockTime(hour: 13, minute: 0))
        #expect(LessonTimeChoices.suggestedStart(for: .morning) == LessonClockTime(hour: 9, minute: 0))
        #expect(LessonTimeChoices.suggestedStart(for: .afternoon) == LessonClockTime(hour: 13, minute: 0))
    }

    @Test("Another time's field gives back exactly the hour and minute it was handed, all day")
    func fieldRoundTrip() {
        for minute in 0..<(24 * 60) {
            let time = LessonClockTime(minutesAfterMidnight: minute)
            #expect(LessonTimeText.clockTime(from: LessonTimeText.fieldDate(time)) == time)
        }
    }

    // MARK: - Text

    @Test("On a 12-hour clock the chip says 10:00 and VoiceOver says 10:00 AM")
    func twelveHourText() {
        #expect(LessonTimeText.chip(LessonClockTime(hour: 10, minute: 0), locale: Self.us) == "10:00")
        #expect(LessonTimeText.chip(LessonClockTime(hour: 8, minute: 45), locale: Self.us) == "8:45")
        #expect(LessonTimeText.chip(LessonClockTime(hour: 13, minute: 15), locale: Self.us) == "1:15")
        #expect(Self.plain(LessonTimeText.spoken(LessonClockTime(hour: 10, minute: 0), locale: Self.us)) == "10:00 AM")
        #expect(Self.plain(LessonTimeText.spoken(LessonClockTime(hour: 15, minute: 15), locale: Self.us)) == "3:15 PM")
        #expect(Self.plain(LessonTimeText.spokenPhrase(LessonClockTime(hour: 10, minute: 0), locale: Self.us))
                == "at 10:00 AM")
    }

    @Test("On a 24-hour clock the chip and VoiceOver both say 13:15",
          arguments: [LessonTimePickerTests.british, LessonTimePickerTests.us24])
    func twentyFourHourText(locale: Locale) {
        #expect(LessonTimeText.chip(LessonClockTime(hour: 13, minute: 15), locale: locale) == "13:15")
        #expect(Self.plain(LessonTimeText.spoken(LessonClockTime(hour: 13, minute: 15), locale: locale)) == "13:15")
        #expect(LessonTimeText.chip(LessonClockTime(hour: 10, minute: 0), locale: locale) == "10:00")
    }

    // MARK: - Status line

    private static var newYork: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York") ?? .current
        calendar.locale = us
        return calendar
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int, hour: Int = 9) -> Date {
        newYork.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }

    @Test("The sheet's status line names the day, the half and the time")
    func statusLine() {
        let monday = Self.day(2026, 11, 9, hour: 8)
        func line(_ day: Date, _ hour: Int, _ minute: Int) -> String {
            LessonTimeText.statusLine(
                plannedOn: day, at: LessonClockTime(hour: hour, minute: minute),
                now: monday, calendar: Self.newYork, locale: Self.us
            )
        }
        #expect(line(Self.day(2026, 11, 11), 10, 0) == "Planned for Wednesday morning, Nov 11, at 10:00")
        #expect(line(Self.day(2026, 11, 9, hour: 14), 13, 30) == "Planned for this afternoon at 1:30")
        #expect(line(Self.day(2026, 11, 10), 8, 45) == "Planned for tomorrow morning at 8:45")
        // The half comes from the time, not from the hour the date was stored at.
        #expect(line(Self.day(2026, 11, 11, hour: 14), 9, 0) == "Planned for Wednesday morning, Nov 11, at 9:00")
    }

    @Test("A status line across the autumn clock change still names the right day")
    func statusLineAcrossClockChange() {
        // Saturday 2026-10-31, the lesson on Monday 2026-11-02 (the clocks went back on Sunday).
        let saturday = Self.day(2026, 10, 31, hour: 23)
        let line = LessonTimeText.statusLine(
            plannedOn: Self.day(2026, 11, 2, hour: 0), at: LessonClockTime(hour: 13, minute: 0),
            now: saturday, calendar: Self.newYork, locale: Self.us
        )
        #expect(line == "Planned for Monday afternoon, Nov 2, at 1:00")
    }

    // MARK: - Pictures

    private static func picker(current: LessonClockTime?) -> LessonTimePicker {
        LessonTimePicker(
            lessonTitle: "Balancing an Equation with Addition",
            current: current,
            takenMinutes: Set(Self.minutes([(9, 0), (9, 15), (13, 30)])),
            set: { _, _ in },
            remove: {}
        )
    }

    @Test("The picker draws, with a time set and with none, in light and dark",
          arguments: [ColorScheme.light, .dark])
    func pictures(scheme: ColorScheme) throws {
        let width = LessonTimePicker.popoverWidth
        let set = try #require(try LessonTimePictures.save(
            Self.picker(current: LessonClockTime(hour: 10, minute: 0)),
            named: "picker-time-set", scheme: scheme, width: width
        ))
        let none = try #require(try LessonTimePictures.save(
            Self.picker(current: nil), named: "picker-no-time", scheme: scheme, width: width
        ))
        #expect(set != none)
        #expect(!set.isEmpty && !none.isEmpty)
    }
}

// MARK: - Away with a co-teacher

/// The picker's away parts (docs/Plans/Plan - Co-teacher times when
/// scheduling.md, Phase 2): which quick times are marked, what VoiceOver says,
/// what the free chips set, that nothing changes without away times, and
/// pictures. The values are hand-made here; Phase 3 builds them from the day.
extension LessonTimePickerTests {

    /// A Monday shaped like the real one, with made-up children: groups at
    /// 9:15–9:45, 9:50–10:20 and 10:40–11:10; 8:45 is the only free morning
    /// start and the afternoon has no group.
    private static let monday = LessonTimeAway(
        rows: [
            "9:15–9:45 · Mira K, Tova B · Miss Nicole",
            "9:50–10:20 · Shira L · Morah Devora",
            "10:40–11:10 · Mira K · Morah Devora"
        ],
        sentences: [
            9 * 60: "Mira K and Tova B leave at 9:15 for Miss Nicole",
            9 * 60 + 15: "Mira K and Tova B are with Miss Nicole until 9:45",
            9 * 60 + 30: "3 children are away during this lesson",
            9 * 60 + 45: "Shira L leaves at 9:50 for Morah Devora",
            10 * 60: "Shira L is with Morah Devora until 10:20",
            10 * 60 + 15: "Shira L is with Morah Devora until 10:20",
            10 * 60 + 20: "Shira L is with Morah Devora until 10:20",
            10 * 60 + 30: "Mira K leaves at 10:40 for Morah Devora",
            10 * 60 + 45: "Mira K is with Morah Devora until 11:10",
            11 * 60: "Mira K is with Morah Devora until 11:10"
        ],
        suggestions: [8 * 60 + 45],
        freeWords: "Free all afternoon"
    )

    private static func awayPicker(
        current: LessonClockTime? = LessonClockTime(hour: 10, minute: 0),
        taken: [(Int, Int)] = [(9, 15), (13, 30)],
        away: LessonTimeAway?,
        set: @escaping (Int, Int) -> Void = { _, _ in }
    ) -> LessonTimePicker {
        LessonTimePicker(
            lessonTitle: "Balancing an Equation with Addition",
            current: current,
            takenMinutes: Set(minutes(taken)),
            away: away,
            set: set,
            remove: {}
        )
    }

    @Test("Each quick time with a sentence is marked, and only those")
    func markedQuickTimes() {
        let picker = Self.awayPicker(away: Self.monday)
        // 10:20 has a sentence but isn't a quick time, so no button carries it.
        #expect(picker.markedQuickMinutes == Self.minutes([
            (9, 0), (9, 15), (9, 30), (9, 45), (10, 0), (10, 15), (10, 30), (10, 45), (11, 0)
        ]))
        #expect(picker.awaySentence(for: LessonClockTime(hour: 8, minute: 45)) == nil)
        #expect(picker.awaySentence(for: LessonClockTime(hour: 13, minute: 0)) == nil)
        #expect(picker.awaySentence(for: LessonClockTime(hour: 9, minute: 45))
                == "Shira L leaves at 9:50 for Morah Devora")
        #expect(picker.showsAwayNote)
        #expect(picker.showsFreeRow)
    }

    @Test("A marked time's spoken value is its sentence; taken and marked joins the two")
    func spokenValues() {
        let picker = Self.awayPicker(away: Self.monday)
        // 9:15 is taken and marked.
        #expect(picker.spokenValue(for: LessonClockTime(hour: 9, minute: 15))
                == "Already has a lesson. Mira K and Tova B are with Miss Nicole until 9:45")
        // 9:00 is only marked.
        #expect(picker.spokenValue(for: LessonClockTime(hour: 9, minute: 0))
                == "Mira K and Tova B leave at 9:15 for Miss Nicole")
        // 1:30 is only taken; 8:45 is neither.
        #expect(picker.spokenValue(for: LessonClockTime(hour: 13, minute: 30)) == "Already has a lesson")
        #expect(picker.spokenValue(for: LessonClockTime(hour: 8, minute: 45)).isEmpty)
        // The lesson's own time still says who is away during it.
        #expect(picker.spokenValue(for: LessonClockTime(hour: 10, minute: 0))
                == "Shira L is with Morah Devora until 10:20")
    }

    @Test("A free chip sets its own hour and minute, quarter hour or not")
    func chipsSetTheirTime() {
        var picked: [LessonClockTime] = []
        let away = LessonTimeAway(suggestions: Self.minutes([(8, 45), (10, 20), (13, 5), (14, 0)]))
        let picker = Self.awayPicker(away: away) { hour, minute in
            picked.append(LessonClockTime(hour: hour, minute: minute))
        }
        #expect(picker.suggestedTimes.map(\.minutesAfterMidnight) == Self.minutes([(8, 45), (10, 20), (13, 5), (14, 0)]))
        for time in picker.suggestedTimes { picker.choose(time) }
        #expect(picked == [
            LessonClockTime(hour: 8, minute: 45), LessonClockTime(hour: 10, minute: 20),
            LessonClockTime(hour: 13, minute: 5), LessonClockTime(hour: 14, minute: 0)
        ])
    }

    @Test("The free row keeps to four chips, and shows the words alone when there are no chips")
    func freeRowLimits() {
        let many = Self.awayPicker(away: LessonTimeAway(suggestions: Self.minutes([
            (8, 45), (9, 0), (10, 20), (13, 0), (14, 0), (15, 0)
        ])))
        #expect(many.suggestedTimes.count == LessonTimePicker.maxSuggestions)
        #expect(many.suggestedTimes.last == LessonClockTime(hour: 13, minute: 0))

        let wordsOnly = Self.awayPicker(away: LessonTimeAway(freeWords: "Free all morning"))
        #expect(wordsOnly.showsFreeRow)
        #expect(wordsOnly.suggestedTimes.isEmpty)
        #expect(!wordsOnly.showsAwayNote)
    }

    @Test("With no away times, or empty ones, nothing new shows",
          arguments: [nil, LessonTimeAway(), LessonTimeAway(rows: [], sentences: [:], suggestions: [], freeWords: "")])
    func nothingNewWithoutAway(away: LessonTimeAway?) {
        let picker = Self.awayPicker(away: away)
        #expect(picker.away == nil)
        #expect(picker.markedQuickMinutes.isEmpty)
        #expect(!picker.showsAwayNote)
        #expect(!picker.showsFreeRow)
        #expect(picker.suggestedTimes.isEmpty)
        #expect(picker.spokenValue(for: LessonClockTime(hour: 9, minute: 15)) == "Already has a lesson")
    }

    @Test("The away mark is a real symbol, and not the cards' Absent one")
    func awaySymbolExists() {
        #expect(LessonTimePicker.awaySymbol != "person.slash")
        #if os(macOS)
        #expect(NSImage(systemSymbolName: LessonTimePicker.awaySymbol, accessibilityDescription: nil) != nil)
        #else
        #expect(UIImage(systemName: LessonTimePicker.awaySymbol) != nil)
        #endif
    }

    @Test("With no away times the picker draws the same as it did before",
          arguments: [ColorScheme.light, .dark])
    func noAwayDrawsAsBefore(scheme: ColorScheme) throws {
        let width = LessonTimePicker.popoverWidth
        let before = try #require(LessonTimePictures.png(
            Self.picker(current: LessonClockTime(hour: 10, minute: 0)), scheme: scheme, width: width
        ))
        let withNil = try #require(LessonTimePictures.png(
            Self.awayPicker(taken: [(9, 0), (9, 15), (13, 30)], away: nil), scheme: scheme, width: width
        ))
        let withEmpty = try #require(LessonTimePictures.png(
            Self.awayPicker(taken: [(9, 0), (9, 15), (13, 30)], away: LessonTimeAway()), scheme: scheme, width: width
        ))
        #expect(withNil == before)
        #expect(withEmpty == before)
    }

    @Test("The picker draws with away times, in light and dark",
          arguments: [ColorScheme.light, .dark])
    func awayPictures(scheme: ColorScheme) throws {
        let width = LessonTimePicker.popoverWidth
        let away = try #require(try LessonTimePictures.save(
            Self.awayPicker(away: Self.monday), named: "picker-away", scheme: scheme, width: width
        ))
        let plain = try #require(try LessonTimePictures.save(
            Self.awayPicker(taken: [(9, 0), (9, 15), (13, 30)], away: nil),
            named: "picker-no-away", scheme: scheme, width: width
        ))
        #expect(away != plain)
        #expect(!away.isEmpty)
    }
}
