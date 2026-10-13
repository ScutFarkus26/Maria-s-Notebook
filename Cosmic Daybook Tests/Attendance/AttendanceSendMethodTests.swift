import Foundation
import CoreData
import Testing
import UserNotifications
@testable import CosmicDaybook

/// Schema 18: how the day's attendance goes to the school (the front-desk
/// email or ParentLocker), carried on the shared settings row, and which way
/// each send went. Older rows, sends and backups read as email.
@Suite("Attendance send method (schema 18)")
@MainActor
struct AttendanceSendMethodTests {

    private func day(_ iso: String) throws -> Date {
        try CoreDataTestHelpers.day(iso)
    }

    private static let emailSettings = AttendanceEmailLog.Settings(
        isEnabled: true,
        toAddresses: "office@school.org",
        nameOrder: .firstLast,
        groupByLevel: false
    )

    private static var parentLockerSettings: AttendanceEmailLog.Settings {
        var settings = emailSettings
        settings.sendMethod = .parentLocker
        return settings
    }

    // MARK: - Older records

    @Test("A settings row and a send from before schema 18 read as email")
    func olderRowsReadAsEmail() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let row = CDAttendanceEmailSettings(context: ctx)
        row.toAddresses = "office@school.org"
        let send = AttendanceEmailLog.recordSend(on: try day("2026-10-12"), role: .assistant, in: ctx)
        #expect(CoreDataTestHelpers.save(ctx))

        #expect(row.sendMethodRaw == "email", "the model's default")
        #expect(row.parentLockerSite == nil)
        let settings = try #require(AttendanceEmailLog.settings(in: ctx))
        #expect(settings.sendMethod == .email)
        #expect(settings.parentLockerSite == "yyli.parentlocker.com")
        #expect(settings.canSend)
        #expect(send.channelRaw == "email")
        #expect(AttendanceEmailLog.Send(send).channel == .email)

        // A value this build doesn't know reads as email too.
        row.sendMethodRaw = "carrierPigeon"
        send.channelRaw = "carrierPigeon"
        #expect(AttendanceEmailLog.settings(in: ctx)?.sendMethod == .email)
        #expect(AttendanceEmailLog.Send(send).channel == .email)
    }

    // MARK: - Sends

    @Test("A send's channel round-trips through the store and words its summary")
    func channelRoundTrips() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let monday = try day("2026-10-12")
        let at = monday.addingTimeInterval(8 * 3_600 + 47 * 60)
        let time = at.formatted(date: .omitted, time: .shortened)
        let record = AttendanceEmailLog.recordSend(
            on: monday, role: .assistant, channel: .parentLocker, now: at, in: ctx
        )
        #expect(CoreDataTestHelpers.save(ctx))
        #expect(record.channelRaw == "parentLocker")

        ctx.refreshAllObjects()
        let latest = try #require(AttendanceEmailLog.latestSend(on: monday, in: ctx))
        #expect(latest.channel == .parentLocker)
        #expect(latest.summary(senderName: "Sarah", for: monday) == "Sent to ParentLocker \(time) by Sarah")

        record.wasConfirmedByHand = true
        #expect(AttendanceEmailLog.Send(record).summary(senderName: "Sarah", for: monday)
            == "Marked as sent to ParentLocker \(time) by Sarah")

        let email = AttendanceEmailLog.recordSend(on: monday, role: .assistant, now: at, in: ctx)
        #expect(email.channelRaw == "email")
        #expect(AttendanceEmailLog.Send(email).summary(senderName: "Sarah", for: monday) == "Emailed \(time) by Sarah")
    }

    // MARK: - Settings

    @Test("The method and site reach the shared row, and picking ParentLocker turns the email off there")
    func settingsTravel() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let guide = stack.viewContext
        #expect(AttendanceEmailLog.saveSettings(Self.emailSettings, role: .leadGuide, in: guide))
        #expect(CoreDataTestHelpers.save(guide))

        var picked = Self.parentLockerSettings
        picked.parentLockerSite = "  https://YYLI.ParentLocker.com/sis/newattendance.php "
        #expect(AttendanceEmailLog.saveSettings(picked, role: .leadGuide, in: guide))
        #expect(CoreDataTestHelpers.save(guide))

        // Another context on the same store, as the share delivers it.
        let assistant = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        assistant.persistentStoreCoordinator = guide.persistentStoreCoordinator
        let row = try #require(assistant.safeFetchFirst(CDFetchRequest(CDAttendanceEmailSettings.self)))
        #expect(row.sendMethodRaw == "parentLocker")
        #expect(row.parentLockerSite == "yyli.parentlocker.com")
        #expect(!row.isEnabled, "an Assistant from before schema 18 stops offering the email")
        let read = try #require(AttendanceEmailLog.settings(in: assistant))
        #expect(read.sendMethod == .parentLocker)
        #expect(read.parentLockerSite == "yyli.parentlocker.com")
        #expect(!read.canSend, "no email with ParentLocker picked")
        #expect(read.canSendAttendance)
        #expect(read.toAddresses == "office@school.org", "the email's recipients stay for a switch back")

        // The guide's own switch is still on in his preferences: saving the
        // same choice again writes nothing.
        #expect(!AttendanceEmailLog.saveSettings(picked, role: .leadGuide, in: guide), "unchanged")
        #expect(!AttendanceEmailLog.saveSettings(Self.parentLockerSettings, role: .leadGuide, in: guide), "same host")

        // Back to email: the email is on again for every build.
        #expect(AttendanceEmailLog.saveSettings(Self.emailSettings, role: .leadGuide, in: guide))
        #expect(CoreDataTestHelpers.save(guide))
        let back = try #require(AttendanceEmailLog.settings(in: guide))
        #expect(back.sendMethod == .email)
        #expect(back.isEnabled)
        #expect(back.canSend)
        #expect(guide.safeFetch(CDFetchRequest(CDAttendanceEmailSettings.self)).count == 1)
    }

    @Test("An assistant can't change the method")
    func onlyTheGuidePicks() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        #expect(AttendanceEmailLog.saveSettings(Self.emailSettings, role: .leadGuide, in: ctx))
        #expect(CoreDataTestHelpers.save(ctx))
        #expect(!AttendanceEmailLog.saveSettings(Self.parentLockerSettings, role: .assistant, in: ctx))
        #expect(AttendanceEmailLog.settings(in: ctx)?.sendMethod == .email)
    }

    @Test("Whether attendance has somewhere to go, by method")
    func canSendByMethod() {
        var settings = Self.parentLockerSettings
        settings.isEnabled = false
        settings.toAddresses = ""
        #expect(settings.canSendAttendance, "ParentLocker needs no email set up")
        #expect(!settings.canSend)

        var email = Self.emailSettings
        #expect(email.canSendAttendance)
        email.isEnabled = false
        #expect(!email.canSendAttendance)
    }

    @Test("The site is kept as its host, and a blank one reads as the school's")
    func siteHost() {
        #expect(AttendanceEmailLog.parentLockerHost(nil) == "yyli.parentlocker.com")
        #expect(AttendanceEmailLog.parentLockerHost("   ") == "yyli.parentlocker.com")
        #expect(AttendanceEmailLog.parentLockerHost("HTTPS://Other.ParentLocker.com/") == "other.parentlocker.com")
        #expect(AttendanceEmailLog.parentLockerHost("http://x.parentlocker.com?a=1") == "x.parentlocker.com")
        #expect(AttendanceEmailLog.parentLockerHost("yyli.parentlocker.com") == "yyli.parentlocker.com")
    }

    @Test("The guide's method and site sync between his devices and go into a preferences backup")
    func preferenceKeysSync() {
        for key in [AttendanceEmailPrefs.sendMethodKey, AttendanceEmailPrefs.parentLockerSiteKey] {
            #expect(SyncedPreferencesStore.syncedKeys.contains(key), "\(key)")
            #expect(BackupPreferencesService.preferenceKeys.contains(key), "\(key)")
        }
    }

    // MARK: - Reminder

    @Test("The reminder is worded for ParentLocker, and rings with ParentLocker picked")
    func reminderOffersParentLocker() async throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        var settings = Self.parentLockerSettings
        settings.toAddresses = ""
        #expect(AttendanceEmailLog.saveSettings(settings, role: .leadGuide, in: ctx))
        #expect(CoreDataTestHelpers.save(ctx))

        let suite = "AttendanceSendMethodTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: FrontDeskEmailReminder.enabledKey)
        let center = SendMethodReminderCenter()
        let now = try day("2026-10-12").addingTimeInterval(7 * 3_600)

        await FrontDeskEmailReminder.reschedule(in: ctx, now: now, center: center, defaults: defaults)

        let titles = Set(center.pending.values.map(\.content.title))
        let dueAt = FrontDeskEmailReminder.timeString(540)
        #expect(titles == ["Attendance due in ParentLocker at \(dueAt)", "ParentLocker attendance is late"])
        #expect(center.pending.values.allSatisfy { FrontDeskEmailReminder.isReminder($0.identifier) })
        let bodies = Set(center.pending.values.map(\.content.body))
        #expect(bodies.contains("Today's attendance hasn't been sent to ParentLocker yet."))

        // Back to an email that's turned off: nothing to remind about.
        var off = Self.emailSettings
        off.isEnabled = false
        #expect(AttendanceEmailLog.saveSettings(off, role: .leadGuide, in: ctx))
        #expect(CoreDataTestHelpers.save(ctx))
        await FrontDeskEmailReminder.reschedule(in: ctx, now: now, center: center, defaults: defaults)
        #expect(center.pending.isEmpty)
    }

    @Test("The email's reminder keeps its words")
    func emailReminderWording() {
        let dueAt = FrontDeskEmailReminder.timeString(540)
        let kinds = FrontDeskEmailReminder.kinds(for: Self.emailSettings, leadMinutes: 10)
        #expect(kinds.map(\.title) == ["Front desk email due at \(dueAt)", "Front desk email is late"])
        #expect(kinds.map(\.minutes) == [530, 540])
        let parentLocker = FrontDeskEmailReminder.kinds(for: Self.parentLockerSettings, leadMinutes: 10)
        #expect(parentLocker.map(\.suffix) == kinds.map(\.suffix), "the same identifiers, so a switch replaces them")
        #expect(parentLocker.map(\.minutes) == [530, 540])
    }
}

/// A notification center that allows everything and remembers what's pending.
@MainActor
private final class SendMethodReminderCenter: ReminderCenter {
    private(set) var pending: [String: UNNotificationRequest] = [:]

    func authorizationStatus() async -> UNAuthorizationStatus { .authorized }
    func requestAuthorization() async -> Bool { true }
    func pendingRequests() async -> [UNNotificationRequest] { Array(pending.values) }

    func removePendingRequests(withIdentifiers identifiers: [String]) {
        for id in identifiers { pending[id] = nil }
    }

    func add(_ request: UNNotificationRequest) async throws {
        pending[request.identifier] = request
    }
}
