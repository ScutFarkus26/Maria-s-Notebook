import Foundation
import CoreData
import Testing
import UserNotifications
@testable import CosmicDaybook

/// The classroom's time zone (domain-logic review A4): the app's calendar is
/// pinned to it, so a device in another zone reads the class's days, and day
/// math holds on a day that starts at 1:00.
///
/// The first test only runs with the test host's own zone shifted:
/// `TEST_RUNNER_TZ=GMT-0800` on the `xcodebuild test-without-building` line.
/// Without it, it reports as skipped.
@Suite("Classroom time zone")
@MainActor
struct ClassroomTimeZoneTests {

    private static let newYork = "America/New_York"

    /// The zone the run shifted the test host to, when it did.
    nonisolated private static var shiftedZone: String? { ProcessInfo.processInfo.environment["TZ"] }

    private func day(_ year: Int, _ month: Int, _ day: Int, in calendar: Calendar) throws -> Date {
        try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
    }

    // MARK: - Another zone

    @Test(
        "A device in another zone reads the class's day",
        .enabled(if: ClassroomTimeZoneTests.shiftedZone != nil)
    )
    func deviceInAnotherZoneReadsTheSameDay() async throws {
        let deviceZone = try #require(Self.shiftedZone)
        #expect(TimeZone.current.identifier == deviceZone)
        let classroom = AppCalendar.calendar(inZone: Self.newYork)
        try #require(classroom.timeZone.secondsFromGMT() != TimeZone.current.secondsFromGMT())

        // 1:00 and 23:00 on November 20 in the classroom: by the device's
        // own clock, one of them is another day.
        let classDay = try day(2026, 11, 20, in: classroom)
        let early = classDay.addingTimeInterval(3_600)
        let late = classDay.addingTimeInterval(23 * 3_600)
        try #require(Set([early, late].map { Calendar.current.startOfDay(for: $0) }).count == 2)

        try await AppCalendar.$pinnedForTesting.withValue(classroom) {
            #expect(AppCalendar.startOfDay(early) == classDay)
            #expect(AppCalendar.startOfDay(late) == classDay)
            #expect(AppCalendar.isSameDay(early, late))

            // The mark a classroom device saved is the one this device finds
            // and marks again: no second record for the day.
            let ctx = try CoreDataTestHelpers.makeContext()
            let student = CoreDataTestHelpers.seedStudent(in: ctx)
            let saved = CoreDataTestHelpers.seedAttendance(in: ctx, studentID: try #require(student.id), date: classDay)
            saved.status = .absent
            let store = CDAttendanceStore(context: ctx, role: .leadGuide)
            for moment in [early, late] {
                #expect(try store.loadRecords(for: moment) == [saved])
                #expect(try store.ensureRecord(for: student, on: moment) == saved)
            }
            #expect(ctx.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).count == 1)

            // The day's send and lock are found from either end of the day.
            AttendanceEmailLog.recordSend(on: late, role: .leadGuide, now: early, in: ctx)
            #expect(AttendanceEmailLog.latestSend(on: early, in: ctx) != nil)
            AttendanceDayLocks.setLocked(true, for: early, role: .leadGuide, in: ctx)
            #expect(AttendanceDayLocks.isLocked(late, in: ctx))

            // The 9:00 deadline is the class's 9:00, and the email names the class's day.
            let nine = try #require(classroom.date(bySettingHour: 9, minute: 0, second: 0, of: classDay))
            let urgency = AttendanceEmailLog.urgency(
                for: classDay, deadlineMinutes: 540, now: nine.addingTimeInterval(-600)
            )
            #expect(urgency == .due(nine))
            #expect(AttendanceEmailReport.makeSubject(for: late).contains("Nov 20"))
            #expect(AttendanceEmailReport.makeSubject(for: early).contains("Nov 20"))

            // Her birthday and her grade are the class's too (review A18): a
            // child born on the class's September 2 is not yet 7 on September 1.
            let birthday = try day(2015, 11, 20, in: classroom)
            #expect(AttendanceBirthday.on(early, birthday: birthday) != nil)
            #expect(AttendanceBirthday.on(late, birthday: birthday) != nil)
            let bornSeptember2 = try day(2019, 9, 2, in: classroom)
            #expect(FloridaGradeCalculator.ageOnSchoolYearStart(birthday: bornSeptember2, referenceDate: late) == 6)

            try await remindersRingAtTheClassroomsNine(classroom: classroom)
        }
    }

    /// The reminder's trigger fires at the class's 8:50 and 9:00, not the
    /// device's: its components carry the classroom's zone.
    private func remindersRingAtTheClassroomsNine(classroom: Calendar) async throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let settings = AttendanceEmailLog.Settings(
            isEnabled: true, toAddresses: "office@school.org", nameOrder: .firstLast, groupByLevel: false
        )
        #expect(AttendanceEmailLog.saveSettings(settings, role: .leadGuide, in: ctx))
        let name = "ClassroomTimeZoneTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: FrontDeskEmailReminder.enabledKey)

        let requests = await FrontDeskEmailReminder.wantedRequests(
            in: ctx, now: Date(), center: AllowedReminderCenter(), defaults: defaults
        )
        try #require(!requests.isEmpty)
        for request in requests {
            let trigger = try #require(request.trigger as? UNCalendarNotificationTrigger)
            let next = try #require(trigger.nextTriggerDate())
            let minutes = classroom.component(.hour, from: next) * 60 + classroom.component(.minute, from: next)
            #expect([530, 540].contains(minutes), "fires at \(minutes) minutes into the class's day")
        }
    }

    // MARK: - A day that starts at 1:00

    @Test("A day that starts at 1:00 keeps whole days")
    func dayThatStartsAtOne() throws {
        if let shifted = Self.shiftedZone { #expect(TimeZone.current.identifier == shifted) }
        // Havana's clocks go forward at midnight: March 8, 2026 starts at 1:00.
        let havana = AppCalendar.calendar(inZone: "America/Havana")
        let noon = try #require(havana.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))
        let start = havana.startOfDay(for: noon)
        try #require(havana.component(.hour, from: start) == 1)
        let monday = try day(2026, 3, 9, in: havana)

        try AppCalendar.$pinnedForTesting.withValue(havana) {
            // The day ends at the next day's midnight, not an hour into it.
            #expect(AppCalendar.dayRange(for: noon).start == start)
            #expect(AppCalendar.dayRange(for: noon).end == monday)
            #expect(AppCalendar.addingDays(1, to: start) == monday)
            #expect(AppCalendar.dayStart(after: start) == monday)

            // A walk over the days after it still lands on day starts: the
            // next weekend is found as days off.
            let ctx = try CoreDataTestHelpers.makeContext()
            let saturday = try day(2026, 3, 7, in: havana)
            let nextSaturday = try day(2026, 3, 14, in: havana)
            let nextMonday = try day(2026, 3, 16, in: havana)
            let off = SchoolDayChecker.nonSchoolDaySet(in: saturday..<nextMonday, using: ctx, calendar: havana)
            #expect(off == [saturday, start, nextSaturday, try day(2026, 3, 15, in: havana)])
            #expect(AttendanceEmailLog.nonSchoolDays(in: saturday..<nextMonday, using: ctx, calendar: havana) == off)
            #expect(SchoolDayChecker.schoolDaysBetween(start: saturday, end: nextMonday, using: ctx) == 5)
            let dayNumber = AttendanceSchoolDayCount.number(
                of: nextMonday, firstDay: try day(2026, 3, 6, in: havana), nonSchoolDays: off, calendar: havana
            )
            #expect(dayNumber == 7)

            // A record at the day's 1:00 start is that day's; midnight after is the next day's.
            let sunday = CoreDataTestHelpers.seedAttendance(in: ctx, date: start)
            CoreDataTestHelpers.seedAttendance(in: ctx, date: monday)
            let request = CDFetchRequest(CDAttendanceRecord.self)
            request.predicate = AppCalendar.dayPredicate(on: noon)
            #expect(ctx.safeFetch(request) == [sunday])
        }
    }

    /// The school-day steps walk over a day that starts at 1:00 and still
    /// land on midnight: a day added to 1:00 is 1:00 the next day, an hour
    /// into it (cold review, finding 8).
    @Test("Next and previous school days over a day that starts at 1:00 are day starts")
    func schoolDayStepsOverADayThatStartsAtOne() throws {
        if let shifted = Self.shiftedZone { #expect(TimeZone.current.identifier == shifted) }
        let havana = AppCalendar.calendar(inZone: "America/Havana")
        let saturday = try day(2026, 3, 7, in: havana)
        let sunday = try #require(havana.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))
        try #require(havana.component(.hour, from: havana.startOfDay(for: sunday)) == 1)
        let monday = try day(2026, 3, 9, in: havana)
        let friday = try day(2026, 3, 6, in: havana)
        let tuesday = try day(2026, 3, 10, in: havana)
        let nextMonday = try day(2026, 3, 16, in: havana)
        let ctx = try CoreDataTestHelpers.makeContext()
        // Not `.shared`, which the other suites fill as they run.
        let service = SchoolCalendarService()

        AppCalendar.$pinnedForTesting.withValue(havana) {
            #expect(service.nextSchoolDaySync(after: saturday, using: ctx) == monday)
            #expect(service.nextSchoolDaySync(after: friday, using: ctx) == monday)
            #expect(service.previousSchoolDaySync(before: monday, using: ctx) == friday)
            #expect(service.schoolDaySync(onOrAfter: sunday, using: ctx) == monday)
            #expect(service.nearestSchoolDaySync(to: sunday, using: ctx) == monday)
            // A walk past the change keeps landing on midnights.
            #expect(service.nextSchoolDaySync(after: monday, using: ctx) == tuesday)
            #expect(service.schoolDaysBetween(start: saturday, end: nextMonday, using: ctx) == 5)
        }
    }

    /// Turning a day off or on matches the records of that day only: on a
    /// day that starts at 1:00, the range used to run an hour into the next
    /// day and take its record too (cold review, finding 8).
    @Test("Turning a day that starts at 1:00 on or off leaves the next day alone")
    func toggleOnADayThatStartsAtOne() async throws {
        if let shifted = Self.shiftedZone { #expect(TimeZone.current.identifier == shifted) }
        let havana = AppCalendar.calendar(inZone: "America/Havana")
        let sunday = try #require(havana.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12)))
        let monday = try day(2026, 3, 9, in: havana)
        let ctx = try CoreDataTestHelpers.makeContext()
        let mondays = CDSchoolDayOverride(context: ctx)
        mondays.date = monday
        #expect(CoreDataTestHelpers.save(ctx))
        let service = SchoolCalendarService()

        try await AppCalendar.$pinnedForTesting.withValue(havana) {
            // Sunday had no change of its own, so it becomes a school day.
            let isOff = try await service.toggleNonSchoolDay(sunday, using: ctx)
            #expect(!isOff)
        }
        #expect(!mondays.isDeleted)
        let overrides = ctx.safeFetch(CDFetchRequest(CDSchoolDayOverride.self))
        #expect(overrides.count == 2)
        #expect(overrides.contains { $0.date == havana.startOfDay(for: sunday) })
    }

    // MARK: - The zone on the row

    @Test("An unknown or missing zone is the device's own")
    func unknownZoneFallsBack() {
        #expect(AppCalendar.calendar(inZone: Self.newYork).timeZone.identifier == Self.newYork)
        #expect(AppCalendar.calendar(inZone: Self.newYork).identifier == .gregorian)
        let device = TimeZone.current.identifier
        // Identifiers are case-sensitive: this one isn't a zone.
        #expect(AppCalendar.calendar(inZone: "america/new_york").timeZone.identifier == device)
        #expect(AppCalendar.calendar(inZone: "Not/AZone").timeZone.identifier == device)
        #expect(AppCalendar.calendar(inZone: nil).timeZone.identifier == device)

        // The classroom's copy changes only when the row does, and says so.
        let before = ClassroomCalendar.current
        #expect(!ClassroomCalendar.adopt(before))
    }

    @Test("Only the guide sets the zone and session, and they read back from the row")
    func zoneAndSessionOnTheRow() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let calendar = AppCalendar.calendar(inZone: Self.newYork)
        let session = try #require(SchoolSession(
            firstDay: try day(2026, 8, 25, in: calendar), lastDay: try day(2027, 6, 18, in: calendar)
        ))
        let settings = AttendanceEmailLog.Settings(
            isEnabled: true, toAddresses: "office@school.org", nameOrder: .lastFirst, groupByLevel: false
        )
        #expect(AttendanceEmailLog.classroomCalendar(in: ctx) == ClassroomCalendar.Snapshot())

        let refused = AttendanceEmailLog.saveClassroomCalendar(
            timeZoneID: Self.newYork, session: session, base: settings, role: .assistant, in: ctx
        )
        #expect(!refused)
        #expect(AttendanceEmailLog.settings(in: ctx) == nil)

        let written = AttendanceEmailLog.saveClassroomCalendar(
            timeZoneID: Self.newYork, session: session, base: settings, role: .leadGuide, in: ctx
        )
        #expect(written)
        #expect(AttendanceEmailLog.classroomCalendar(in: ctx).timeZoneID == Self.newYork)
        #expect(AttendanceEmailLog.classroomCalendar(in: ctx).session == session)
        #expect(SchoolSession.read(in: ctx) == session)
        // The row it had to make holds the email settings it was given, as a stand-in.
        #expect(AttendanceEmailLog.settings(in: ctx)?.nameOrder == .lastFirst)
        #expect(AttendanceSettingsPendingWrite.rowStamp(in: ctx)?.isLaunchSeed == true)

        // A later attendance-settings save leaves them alone.
        var edited = settings
        edited.groupByLevel = true
        #expect(AttendanceEmailLog.saveSettings(edited, role: .leadGuide, in: ctx))
        #expect(AttendanceEmailLog.classroomCalendar(in: ctx).timeZoneID == Self.newYork)
        #expect(SchoolSession.read(in: ctx) == session)

        // A test's store, like the Sample Class's, never feeds the app-wide
        // calendar: only the app's own store is followed.
        let appWide = ClassroomCalendar.current
        #expect(!ClassroomCalendarFollower.refresh(from: ctx))
        #expect(ClassroomCalendar.current == appWide)
    }

    /// A save of the front-desk settings on a Mac in California used to fill
    /// an unset zone with the Mac's, moving every day already saved at the
    /// class's Eastern midnight back one (cold review, finding 2). Only the
    /// zone picker sets it now.
    @Test("A front-desk settings save never sets the zone")
    func settingsSaveLeavesTheZoneUnset() throws {
        let settings = AttendanceEmailLog.Settings(
            isEnabled: true, toAddresses: "office@school.org", nameOrder: .firstLast, groupByLevel: false
        )
        let launch = try CoreDataTestHelpers.makeContext()
        AttendanceEmailLog.saveSettings(
            settings, role: .leadGuide, now: AttendanceEmailLog.launchSeedStamp, in: launch
        )
        #expect(AttendanceEmailLog.settings(in: launch) != nil)
        #expect(AttendanceEmailLog.classroomCalendar(in: launch).timeZoneID == nil)

        let mac = try CoreDataTestHelpers.makeContext()
        AttendanceEmailLog.saveSettings(settings, role: .leadGuide, in: mac)
        #expect(AttendanceEmailLog.settings(in: mac) != nil)
        #expect(AttendanceEmailLog.classroomCalendar(in: mac).timeZoneID == nil)

        // A duplicate row another device wrote hands its zone to the row kept.
        let two = try CoreDataTestHelpers.makeContext()
        AttendanceEmailLog.saveSettings(settings, role: .leadGuide, in: two)
        let older = CDAttendanceEmailSettings(context: two)
        older.modifiedAt = Date(timeIntervalSinceNow: -3_600)
        older.classroomTimeZoneID = "America/Chicago"
        var edited = settings
        edited.groupByLevel = true
        AttendanceEmailLog.saveSettings(edited, role: .leadGuide, in: two)
        #expect(CoreDataTestHelpers.save(two))
        #expect(two.safeFetch(CDFetchRequest(CDAttendanceEmailSettings.self)).count == 1)
        #expect(AttendanceEmailLog.classroomCalendar(in: two).timeZoneID == "America/Chicago")
    }
}

// MARK: - Changing the zone

extension ClassroomTimeZoneTests {

    /// Moving the class west shows every saved day a day earlier, so the
    /// guide is told first (cold review, finding 2). Moving east keeps them.
    @Test("Changing the zone warns when the days already saved would move")
    func zoneChangeWarning() throws {
        if let shifted = Self.shiftedZone { #expect(TimeZone.current.identifier == shifted) }
        let english = Locale(identifier: "en_US")
        let newYork = try #require(TimeZone(identifier: Self.newYork))
        let losAngeles = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let london = try #require(TimeZone(identifier: "Europe/London"))
        let phoenix = try #require(TimeZone(identifier: "America/Phoenix"))
        let eastern = AppCalendar.calendar(inZone: Self.newYork)
        let autumn = try day(2026, 9, 1, in: eastern)...(try day(2026, 11, 20, in: eastern))

        let west = try #require(SchoolSessionCopy.zoneChangeWarning(
            from: newYork, to: losAngeles, savedDays: autumn, locale: english
        ))
        #expect(west == "Attendance and days off already in the notebook were saved in Eastern Time (New York). "
            + "In Pacific Time (Los Angeles) they would show a day earlier, on every device.")
        let east = SchoolSessionCopy.zoneChangeWarning(from: newYork, to: london, savedDays: autumn, locale: english)
        #expect(east == nil)
        #expect(SchoolSessionCopy.zoneChangeWarning(from: newYork, to: newYork, savedDays: autumn) == nil)
        // Nothing saved yet: nothing to move.
        #expect(SchoolSessionCopy.zoneChangeWarning(from: newYork, to: losAngeles, savedDays: nil) == nil)

        // Phoenix keeps one clock all year, so only its winter days move.
        let mountain = AppCalendar.calendar(inZone: "America/Phoenix")
        let summer = try day(2026, 6, 1, in: mountain)...(try day(2026, 8, 31, in: mountain))
        let winter = try day(2026, 6, 1, in: mountain)...(try day(2026, 12, 15, in: mountain))
        #expect(SchoolSessionCopy.zoneChangeWarning(from: phoenix, to: losAngeles, savedDays: summer) == nil)
        #expect(SchoolSessionCopy.zoneChangeWarning(from: phoenix, to: losAngeles, savedDays: winter) != nil)

        // From this device's own zone, as an unset zone is read: west of it
        // warns, east of it doesn't.
        let device = TimeZone.current
        let deviceDays = AppCalendar.calendar(inZone: nil)
        let span = try day(2026, 9, 1, in: deviceDays)...(try day(2026, 11, 20, in: deviceDays))
        let westward = TimeZone(secondsFromGMT: device.secondsFromGMT() - 3 * 3_600)
        let eastward = TimeZone(secondsFromGMT: device.secondsFromGMT() + 3 * 3_600)
        if let westward, device.secondsFromGMT() - 3 * 3_600 >= -12 * 3_600 {
            let warning = SchoolSessionCopy.zoneChangeWarning(from: device, to: westward, savedDays: span)
            #expect(warning?.contains("a day earlier") == true)
        }
        if let eastward, device.secondsFromGMT() + 3 * 3_600 <= 14 * 3_600 {
            #expect(SchoolSessionCopy.zoneChangeWarning(from: device, to: eastward, savedDays: span) == nil)
        }
    }

    @Test("The days already saved span every record kept by its day")
    func savedDaySpan() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        #expect(SchoolSessionCopy.savedDaySpan(in: ctx) == nil)
        let calendar = AppCalendar.calendar(inZone: Self.newYork)
        let first = try day(2026, 9, 2, in: calendar)
        let middle = try day(2026, 10, 1, in: calendar)
        let last = try day(2026, 12, 21, in: calendar)
        CoreDataTestHelpers.seedAttendance(in: ctx, date: middle)
        let dayOff = CDNonSchoolDay(context: ctx)
        dayOff.date = last
        let lock = CDAttendanceDayLock(context: ctx)
        lock.date = first
        #expect(CoreDataTestHelpers.save(ctx))
        #expect(SchoolSessionCopy.savedDaySpan(in: ctx) == first...last)
    }
}

/// A notification center that allows reminders and keeps nothing.
private final class AllowedReminderCenter: ReminderCenter {
    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func requestAuthorization() async -> Bool { true }
    func pendingRequests() async -> [UNNotificationRequest] { [] }
    func removePendingRequests(withIdentifiers identifiers: [String]) {}
    func add(_ request: UNNotificationRequest) async throws {}
}
