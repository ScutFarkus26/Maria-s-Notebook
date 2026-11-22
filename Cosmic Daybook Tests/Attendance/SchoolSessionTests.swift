import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The school session on the shared settings row (domain-logic review R20):
/// the summer before its first day and after its last day is days off for
/// every reader, and the first day is where the year and Day 1 begin.
@Suite("School session")
@MainActor
struct SchoolSessionTests {

    private let calendar = AppCalendar.shared

    private func day(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    private static let settings = AttendanceEmailLog.Settings(
        isEnabled: true, toAddresses: "office@school.org", nameOrder: .firstLast, groupByLevel: false
    )

    /// August 25, 2026 to June 18, 2027.
    private func session() throws -> SchoolSession {
        try #require(SchoolSession(firstDay: try day(2026, 8, 25), lastDay: try day(2027, 6, 18)))
    }

    private func setSession(in ctx: NSManagedObjectContext) throws {
        let written = AttendanceEmailLog.saveClassroomCalendar(
            timeZoneID: nil, session: try session(), base: Self.settings, role: .leadGuide, in: ctx
        )
        #expect(written)
    }

    private func isWeekday(_ date: Date) -> Bool {
        (2...6).contains(calendar.component(.weekday, from: date))
    }

    // MARK: - Days off

    @Test("A summer weekday is a day off once the session is set")
    func summerWeekdayIsOff() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let july15 = try day(2027, 7, 15)
        try #require(isWeekday(july15))
        let week = try day(2027, 7, 12)..<(try day(2027, 7, 17))

        // Before: every summer weekday counts as a school day.
        #expect(!SchoolDayChecker.isNonSchoolDay(july15, using: ctx))
        #expect(SchoolDayChecker.nonSchoolDaySet(in: week, using: ctx).isEmpty)

        try setSession(in: ctx)
        #expect(SchoolDayChecker.isNonSchoolDay(july15, using: ctx))
        #expect(SchoolDayChecker.nonSchoolDaySet(in: week, using: ctx).count == 5)
        #expect(AttendanceEmailLog.nonSchoolDays(in: week, using: ctx).contains(july15))

        // The last week of school has its five days, and the next school day
        // after the last one is the anniversary of the first.
        let lastDay = try day(2027, 6, 18)
        let lastWeeks = SchoolDayChecker.schoolDaysBetween(
            start: try day(2027, 6, 14), end: try day(2027, 6, 28), using: ctx
        )
        #expect(lastWeeks == 5)
        let next = SchoolDayChecker.nextSchoolDays(from: lastDay, count: 2, using: ctx)
        #expect(next == [lastDay, try day(2027, 8, 25)])
        #expect(try SchoolDayChecker.schoolDay(from: lastDay, forward: true, using: ctx) == day(2027, 8, 25))
    }

    @Test("Only the summers beside the session are off; other years keep their school days")
    func onlyTheSummersBesideIt() throws {
        let session = try session()
        // In session.
        #expect(!session.isOut(try day(2026, 8, 25), calendar: calendar))
        #expect(!session.isOut(try day(2027, 1, 12), calendar: calendar))
        #expect(!session.isOut(try day(2027, 6, 18), calendar: calendar))
        // The summer before, back to July 1, and the summer after, up to a year after the first day.
        #expect(session.isOut(try day(2026, 8, 24), calendar: calendar))
        #expect(session.isOut(try day(2026, 7, 1), calendar: calendar))
        #expect(session.isOut(try day(2027, 6, 19), calendar: calendar))
        #expect(session.isOut(try day(2027, 8, 24), calendar: calendar))
        // Last school year, and next: one session says nothing about them.
        #expect(!session.isOut(try day(2026, 6, 30), calendar: calendar))
        #expect(!session.isOut(try day(2026, 3, 10), calendar: calendar))
        #expect(!session.isOut(try day(2027, 8, 25), calendar: calendar))
        #expect(!session.isOut(try day(2027, 10, 5), calendar: calendar))

        // A day off the guide marked still counts inside the session, and a
        // school Saturday doesn't open a day the session is out on.
        let saturday = try day(2027, 7, 17)
        try #require(calendar.component(.weekday, from: saturday) == 7)
        #expect(SchoolDayChecker.isNonSchoolDay(
            saturday, nonSchoolDayDates: [], overrideDates: [saturday], session: session, calendar: calendar
        ))
        #expect(!SchoolDayChecker.isNonSchoolDay(
            saturday, nonSchoolDayDates: [], overrideDates: [saturday], session: nil, calendar: calendar
        ))
    }

    @Test("A session needs both days, in order")
    func halfSetSessionIsNone() throws {
        #expect(SchoolSession(firstDay: try day(2026, 8, 25), lastDay: nil) == nil)
        #expect(SchoolSession(firstDay: nil, lastDay: try day(2027, 6, 18)) == nil)
        #expect(SchoolSession(firstDay: try day(2027, 6, 18), lastDay: try day(2026, 8, 25)) == nil)

        // A row holding only a first day reads as no session: nothing changes.
        let ctx = try CoreDataTestHelpers.makeContext()
        let row = CDAttendanceEmailSettings(context: ctx)
        row.sessionFirstDay = try day(2026, 8, 25)
        #expect(SchoolSession.read(in: ctx) == nil)
        #expect(!SchoolDayChecker.isNonSchoolDay(try day(2027, 7, 15), using: ctx))
    }

    // MARK: - The reminders

    @Test("The front-desk reminders rest over the summer")
    func remindersRestOverTheSummer() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let july5 = try day(2027, 7, 5)
        let morning = july5.addingTimeInterval(8 * 3_600)
        let range = july5..<(try day(2027, 8, 10))
        func fireDates() -> [Date] {
            FrontDeskEmailReminder.fireDates(
                from: morning, minutes: 540,
                nonSchoolDays: AttendanceEmailLog.nonSchoolDays(in: range, using: ctx),
                todayIsDone: false
            )
        }
        #expect(fireDates().count == FrontDeskEmailReminder.daysAhead)
        try setSession(in: ctx)
        #expect(fireDates().isEmpty)
    }

    // MARK: - Day 1 and the year's start

    @Test("Day 1 is the session's first day, not a stray August mark")
    func dayOneIsTheSessionsFirstDay() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let stray = CoreDataTestHelpers.seedAttendance(in: ctx, date: try day(2026, 8, 5))
        stray.status = .present
        let yearStart = AttendanceSchoolDayCount.yearStart(for: try day(2026, 9, 10), calendar: calendar)
        #expect(try AttendanceSchoolDayCount.firstDay(inYearStarting: yearStart, in: ctx) == day(2026, 8, 5))

        try setSession(in: ctx)
        let first = try #require(AttendanceSchoolDayCount.firstDay(inYearStarting: yearStart, in: ctx))
        #expect(try first == day(2026, 8, 25))
        #expect(AttendanceSchoolDayCount.number(of: try day(2026, 8, 26), firstDay: first, in: ctx) == 2)
        // Next year's count doesn't start from this session.
        let nextYear = AttendanceSchoolDayCount.yearStart(for: try day(2027, 9, 10), calendar: calendar)
        #expect(AttendanceSchoolDayCount.firstDay(inYearStarting: nextYear, in: ctx) == nil)
    }

    @Test("The school year starts on the session's first day, for projects and grades alike")
    func yearStartReadsTheSession() throws {
        let name = "SchoolSessionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(9, forKey: UserDefaultsKeys.schoolYearStartMonth)
        defaults.set(1, forKey: UserDefaultsKeys.schoolYearStartDay)
        let session = try session()
        func start(_ date: Date, _ session: SchoolSession?) -> Date {
            SchoolYear.currentStart(asOf: date, calendar: calendar, session: session, defaults: defaults)
        }

        #expect(try start(day(2026, 11, 3), session) == day(2026, 8, 25))
        // Between the first day and the configured September 1, the new year is already under way.
        #expect(try start(day(2026, 8, 27), session) == day(2026, 8, 25))
        // Before the first day, and a year on, the configured start stands.
        #expect(try start(day(2026, 8, 20), session) == day(2025, 9, 1))
        #expect(try start(day(2027, 9, 14), session) == day(2027, 9, 1))
        #expect(try start(day(2026, 11, 3), nil) == day(2026, 9, 1))

        // One definition: grades read the same start.
        let today = Date()
        #expect(FloridaGradeCalculator.schoolYearStart(for: today) == SchoolYear.currentStart(asOf: today))
    }
}

/// The marks changed since the school was told (review R18), the arrival
/// note that is not a send (A1), and the one source of the notebook's email
/// (A5).
@Suite("Changed since reported")
@MainActor
struct ChangedSinceReportedTests {

    private func tuesday() throws -> Date {
        try #require(AppCalendar.shared.date(from: DateComponents(year: 2026, month: 11, day: 17)))
    }

    private func at(_ hour: Int, _ minute: Int, on day: Date) throws -> Date {
        try #require(AppCalendar.shared.date(bySettingHour: hour, minute: minute, second: 0, of: day))
    }

    // MARK: - R18

    @Test("A Late at 10:30 after the 9:02 send shows one change")
    func lateAfterTheSendIsOneChange() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let day = try tuesday()
        let store = CDAttendanceStore(context: ctx, role: .leadGuide)
        let ari = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Ari")
        let maya = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Maya")

        // The roll as the 9:02 email reported it: Ari here, Maya absent.
        try store.mark(student: ari, status: .present, on: day)
        try store.mark(student: maya, status: .absent, on: day)
        for record in try store.loadRecords(for: day) { record.modifiedAt = try at(8, 40, on: day) }
        #expect(AttendanceEmailLog.changesSinceReported(on: day, in: ctx) == nil, "nothing was sent yet")
        let sentAt = try at(9, 2, on: day)
        AttendanceEmailLog.recordSend(on: day, role: .leadGuide, now: sentAt, in: ctx)
        #expect(AttendanceEmailLog.changesSinceReported(on: day, in: ctx) == nil, "nothing changed since")

        // Maya comes in late. The store stamps the change with the clock, long after 9:02.
        try store.mark(student: maya, status: .tardy, on: day)
        let changes = try #require(AttendanceEmailLog.changesSinceReported(on: day, in: ctx))
        #expect(changes.count == 1)
        #expect(changes.send.sentAt == sentAt)
        let time = AttendanceEmailLog.Send.time(sentAt, reporting: day)
        #expect(changes.line(for: day) == "1 change since \(time) · Send an update")

        // A second child, and the line counts two; an update sent now clears it.
        try store.mark(student: ari, status: .tardy, on: day)
        let two = try #require(AttendanceEmailLog.changesSinceReported(on: day, in: ctx))
        #expect(two.summary(for: day) == "2 changes since \(time)")
        AttendanceEmailLog.recordSend(on: day, role: .leadGuide, now: Date().addingTimeInterval(60), in: ctx)
        #expect(AttendanceEmailLog.changesSinceReported(on: day, in: ctx) == nil)
    }

    @Test("ParentLocker follows today by itself; a day behind it says where to fix it")
    func parentLockerDays() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let day = try tuesday()
        let maya = CoreDataTestHelpers.seedStudent(in: ctx, firstName: "Maya")
        AttendanceEmailLog.recordSend(
            on: day, role: .leadGuide, channel: .parentLocker, now: try at(9, 2, on: day), in: ctx
        )
        try CDAttendanceStore(context: ctx, role: .leadGuide).mark(student: maya, status: .absent, on: day)

        // On the day itself (`now` is that day), ParentLocker takes the change as it happens.
        #expect(AttendanceEmailLog.changesSinceReported(on: day, now: try at(11, 0, on: day), in: ctx) == nil)
        let later = try #require(AttendanceEmailLog.changesSinceReported(on: day, in: ctx))
        #expect(later.line(for: day).hasSuffix(" · Update it in ParentLocker"))
    }

    // MARK: - A1

    @Test("An arrival-closed note is never counted as a send")
    func closeRowIsNoSend() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let day = try tuesday()
        let closedAt = try at(9, 0, on: day)
        let note = CDAttendanceEmailSend(context: ctx)
        note.date = day
        note.sentAt = closedAt
        note.sentBy = CDClassroomMembership.ClassroomRole.assistant.rawValue
        note.channelRaw = AttendanceEmailLog.arrivalClosedChannel

        #expect(AttendanceEmailLog.latestSend(on: day, in: ctx) == nil)
        #expect(AttendanceEmailLog.sends(on: day, in: ctx).isEmpty)
        #expect(AttendanceEmailLog.daySends(on: day, in: ctx) == nil)
        #expect(AttendanceEmailLog.dayRecords(on: day, in: ctx).sends.isEmpty)
        #expect(!AttendanceEmailLog.dayRecords(on: day, in: ctx).isNotExpected)
        #expect(AttendanceEmailLog.thirdPersonSummary(on: day, in: ctx) == nil)
        #expect(AttendanceEmailLog.changesSinceReported(on: day, in: ctx) == nil)
        // It is still there to read, with the close's time.
        #expect(AttendanceEmailLog.channels(on: day, in: ctx) == [AttendanceEmailLog.arrivalClosedChannel])
        #expect(AttendanceEmailLog.arrivalClosedAt(on: day, in: ctx) == closedAt)
        #expect(AttendanceEmailLog.arrivalClosedAt(on: day.addingTimeInterval(86_400), in: ctx) == nil)

        // A real send beside it is the day's send.
        let emailed = try at(9, 5, on: day)
        AttendanceEmailLog.recordSend(on: day, role: .assistant, now: emailed, in: ctx)
        #expect(AttendanceEmailLog.latestSend(on: day, in: ctx)?.sentAt == emailed)
        #expect(AttendanceEmailLog.sends(on: day, in: ctx).count == 1)
    }

    @Test("The Late rule takes the close's time from the note")
    func lateRuleReadsTheCloseTime() throws {
        let day = try tuesday()
        let noted = try at(9, 0, on: day)

        /// Whether the day still reads closed after the automatic absence is
        /// undone, with a child marked Late at 9:02: before the absence's own
        /// 9:05, after the note's 9:00.
        func staysClosed(closedAt: Date?) throws -> Bool {
            let ctx = try CoreDataTestHelpers.makeContext()
            let name = "ChangedSinceReportedTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let ari = CoreDataTestHelpers.seedAttendance(in: ctx, date: day)
            ari.status = .absent
            ari.absenceReasonRaw = AttendanceDeduplication.automaticAbsenceRaw
            ari.markedAt = try at(9, 5, on: day)
            let maya = CoreDataTestHelpers.seedAttendance(in: ctx, date: day)
            maya.status = .tardy
            maya.markedAt = try at(9, 2, on: day)
            #expect(AttendanceLatePhase.closedAnywhere(
                on: day, records: [ari, maya], closedAt: closedAt, defaults: defaults
            ))
            ari.status = .unmarked
            ari.absenceReasonRaw = AbsenceReason.none.rawValue
            ari.markedAt = nil
            return AttendanceLatePhase.closedAnywhere(
                on: day, records: [ari, maya], closedAt: closedAt, defaults: defaults
            )
        }

        #expect(try staysClosed(closedAt: noted), "Maya came in after the noted close: the day stays closed")
        #expect(try !staysClosed(closedAt: nil), "without the note the close is dated 9:05, after her mark")
    }

    // MARK: - A5

    @Test("The notebook's email is written from the shared row, not this device's preferences")
    func emailReadsTheSharedRow() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let preferences = AttendanceEmailLog.Settings(
            isEnabled: true, toAddresses: "old@school.org", nameOrder: .firstLast, groupByLevel: false
        )
        let students = [AttendanceEmailStudent(firstName: "Bo", lastName: "Adams", level: .upper)]
        func draft() -> AttendanceEmailDraft {
            AttendanceEmail.emailSettings(in: ctx, isSampleClass: false, preferences: preferences)
                .draft(for: Date(), present: students, tardy: [], absent: [])
        }

        // No row yet, or only the launch's stand-in: the preferences write it.
        #expect(draft().recipients == ["old@school.org"])
        AttendanceEmailLog.saveSettingsIfMissing(preferences, role: .leadGuide, in: ctx)
        #expect(draft().recipients == ["old@school.org"])

        // The guide's own row, as an edit on another device left it.
        let row = AttendanceEmailLog.Settings(
            isEnabled: true, toAddresses: "office@school.org, nurse@school.org", nameOrder: .lastFirst,
            groupByLevel: false
        )
        #expect(AttendanceEmailLog.saveSettings(row, role: .leadGuide, in: ctx))
        #expect(draft().recipients == ["office@school.org", "nurse@school.org"])
        #expect(draft().body.contains("Adams, Bo"))
        // The Assistant writes the same email from the same row.
        let assistants = try #require(AttendanceEmailLog.settings(in: ctx))
            .draft(for: Date(), present: students, tardy: [], absent: [])
        #expect(assistants.body == draft().body)
        #expect(assistants.subject == draft().subject)
    }
}
