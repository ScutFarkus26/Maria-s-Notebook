import Foundation
import Testing
@testable import CosmicDaybook

/// The words Today's header says (the Mac window subtitle and the attendance
/// band's VoiceOver line) and when the toolbar's sync dot shows.
@Suite("Today header text")
@MainActor
struct TodayHeaderTextTests {

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: dayOfMonth, hour: 0))!
    }

    // MARK: - Subtitle

    @Test("The subtitle names the weekday, month and day, with no year")
    func subtitleFormat() {
        let locale = Locale(identifier: "en_US")
        #expect(TodayHeaderText.subtitle(for: day(2026, 9, 23), locale: locale, calendar: calendar)
            == "Wednesday, September 23")
        #expect(TodayHeaderText.subtitle(for: day(2026, 10, 2), locale: locale, calendar: calendar)
            == "Friday, October 2")
    }

    @Test("Midnight in the calendar's own time zone stays on that day")
    func subtitleUsesCalendarTimeZone() {
        let locale = Locale(identifier: "en_US")
        #expect(TodayHeaderText.subtitle(for: day(2026, 8, 25), locale: locale, calendar: calendar)
            == "Tuesday, August 25")
    }

    // MARK: - Attendance band

    @Test("Everyone here reads as the count alone")
    func everyoneHere() {
        let summary = TodayAttendanceBandSummary(hereCount: 22, lateCount: 0, absentCount: 0, leftEarlyCount: 0)
        #expect(summary.accessibilityLabel == "22 here")
        #expect(summary.lateText == nil)
        #expect(summary.absentText == nil)
        #expect(summary.lateHelp.isEmpty)
    }

    @Test("Late before its names load, then absent children named")
    func lateAndAbsent() {
        let summary = TodayAttendanceBandSummary(
            hereCount: 19, lateCount: 2, absentCount: 3, leftEarlyCount: 0,
            absentNames: ["Chaviva F", "Leora F", "Zahava W"]
        )
        #expect(summary.hereText == "19 here")
        #expect(summary.lateText == "2 late")
        #expect(summary.absentText == "3 absent")
        #expect(summary.accessibilityLabel == "19 here, 2 late, 3 absent: Chaviva F, Leora F, Zahava W")
        #expect(summary.lateHelp == "2 late")
    }

    @Test("Late names, once loaded, fill the tooltip and the VoiceOver line")
    func lateNamesLoaded() {
        let summary = TodayAttendanceBandSummary(
            hereCount: 19, lateCount: 2, absentCount: 1, leftEarlyCount: 0,
            lateNames: ["Maya S", "Ora P"], absentNames: ["Leora F"]
        )
        #expect(summary.lateHelp == "Late: Maya S, Ora P")
        #expect(summary.accessibilityLabel == "19 here, 2 late: Maya S, Ora P; 1 absent: Leora F")
    }

    @Test("Left early follows absent, set off by a semicolon")
    func leftEarly() {
        let summary = TodayAttendanceBandSummary(
            hereCount: 20, lateCount: 0, absentCount: 1, leftEarlyCount: 1,
            absentNames: ["Leora F"], leftEarlyNames: ["Naomi F"]
        )
        #expect(summary.leftEarlyText == "1 left early")
        #expect(summary.accessibilityLabel == "20 here, 1 absent: Leora F; 1 left early: Naomi F")
    }

    // MARK: - Sync dot

    @Test("The sync dot hides only while sync is idle and fine")
    func syncDotVisibility() {
        #expect(SyncDotVisibility.isShown(
            isNetworkAvailable: true, isSyncing: false, pendingLocalChanges: 0, hasError: false
        ) == false)
        #expect(SyncDotVisibility.isShown(
            isNetworkAvailable: true, isSyncing: true, pendingLocalChanges: 0, hasError: false
        ))
        #expect(SyncDotVisibility.isShown(
            isNetworkAvailable: true, isSyncing: false, pendingLocalChanges: 3, hasError: false
        ))
        #expect(SyncDotVisibility.isShown(
            isNetworkAvailable: true, isSyncing: false, pendingLocalChanges: 0, hasError: true
        ))
        #expect(SyncDotVisibility.isShown(
            isNetworkAvailable: false, isSyncing: false, pendingLocalChanges: 0, hasError: false
        ))
    }
}
