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
