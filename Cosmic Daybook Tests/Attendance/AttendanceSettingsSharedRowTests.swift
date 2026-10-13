import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-13 afternoon, H1. The morning's repair copied this
// device's iCloud preferences over the shared settings row whenever the two
// differed, stamped newest, so an iPad whose preferences hadn't caught up
// switched the whole class back to email just by opening Settings, and any
// edit there did the same. Settings now shows the row, writes only the field
// that was edited, writes only from the person's own actions, and puts right
// only a write this device itself put off. Also L3 (the address goes in on
// Return or closing) and M9's screen side (the sign-in row).

/// This device's side of the settings, kept inside the test: the
/// preferences it reads, what it copies into them, and its own defaults
/// for a pending write. The real preferences are never touched.
final class AttendanceSettingsTestDevice {
    var preferences: AttendanceEmailLog.Settings
    private(set) var written: [String: Any] = [:]
    let defaults: UserDefaults

    init(preferences: AttendanceEmailLog.Settings) throws {
        self.preferences = preferences
        defaults = try #require(UserDefaults(suiteName: "AttendanceSettingsSharedRowTests.\(UUID().uuidString)"))
    }

    var writtenKeys: Set<String> { Set(written.keys) }

    var pending: AttendanceSettingsPendingWrite? { AttendanceSettingsPendingWrite.load(from: defaults) }

    var settings: AttendanceEmail.DeviceSettings {
        AttendanceEmail.DeviceSettings(
            stored: { [unowned self] in preferences },
            setPreference: { [unowned self] key, value in written[key] = value },
            defaults: defaults
        )
    }
}

@Suite("Attendance settings and the shared row")
@MainActor
struct AttendanceSettingsSharedRowTests {

    static let emailSettings = AttendanceEmailLog.Settings(
        isEnabled: true, toAddresses: "office@school.org", nameOrder: .firstLast, groupByLevel: false
    )

    private static var parentLockerSettings: AttendanceEmailLog.Settings {
        var settings = emailSettings
        settings.sendMethod = .parentLocker
        settings.parentLockerSite = "school.parentlocker.com"
        settings.deadlineMinutes = 8 * 60 + 45
        return settings
    }

    private static let earlier = Date(timeIntervalSinceReferenceDate: 813_000_000)

    /// Another context on the same store, as the guide's other devices and the assistants read it.
    func reader(for context: NSManagedObjectContext) -> NSManagedObjectContext {
        let other = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        other.persistentStoreCoordinator = context.persistentStoreCoordinator
        return other
    }

    // MARK: - H1

    @Test("A device whose preferences are behind writes nothing as Settings opens, and shows the row")
    func laggingDeviceWritesNothing() throws {
        let guide = try CoreDataTestHelpers.makeContext()
        #expect(AttendanceEmailLog.saveSettings(
            Self.parentLockerSettings, role: .leadGuide, now: Self.earlier, in: guide
        ))
        #expect(CoreDataTestHelpers.save(guide))
        // iCloud hasn't brought this iPad's preferences up to date: they still say email.
        let device = try AttendanceSettingsTestDevice(preferences: Self.emailSettings)

        #expect(!AttendanceEmail.writePendingEdit(
            in: guide, isSampleClass: false, device: device.settings, firstDownloadPending: false
        ))

        #expect(!guide.hasChanges)
        #expect(device.written.isEmpty)
        let row = try #require(AttendanceEmailLog.settings(in: reader(for: guide)))
        #expect(row.sendMethod == .parentLocker)
        #expect(AttendanceSettingsPendingWrite.rowStamp(in: guide)?.modifiedAt == Self.earlier)

        let shown = AttendanceEmail.shownSettings(row: row, preferences: device.preferences, isSampleClass: false)
        #expect(shown.sendMethod == .parentLocker)
        #expect(shown.parentLockerSite == "school.parentlocker.com")
        #expect(shown.deadlineMinutes == 8 * 60 + 45)
        #expect(shown.toAddresses == "office@school.org", "the email's own fields stay this device's")
    }

    @Test("A new due time on a device that's behind changes only the due time")
    func deadlineEditKeepsTheMethod() throws {
        let guide = try CoreDataTestHelpers.makeContext()
        var row = Self.parentLockerSettings
        row.toAddresses = "new-office@school.org"
        #expect(AttendanceEmailLog.saveSettings(row, role: .leadGuide, now: Self.earlier, in: guide))
        #expect(CoreDataTestHelpers.save(guide))
        let device = try AttendanceSettingsTestDevice(preferences: Self.emailSettings)

        #expect(AttendanceEmail.shareEdit(
            AttendanceSettingsEdit(deadlineMinutes: 8 * 60 + 30),
            in: guide, isSampleClass: false, device: device.settings, firstDownloadPending: false
        ))

        let shared = try #require(AttendanceEmailLog.settings(in: reader(for: guide)))
        #expect(shared.deadlineMinutes == 8 * 60 + 30)
        #expect(shared.sendMethod == .parentLocker, "the class stays on ParentLocker")
        #expect(shared.parentLockerSite == "school.parentlocker.com")
        #expect(shared.toAddresses == "new-office@school.org", "the row's other fields stay")
        #expect(!shared.isEnabled)
        #expect(device.writtenKeys == [AttendanceEmailPrefs.deadlineKey])
        #expect(device.written[AttendanceEmailPrefs.deadlineKey] as? Int == 8 * 60 + 30)
    }

    @Test("A change synced in while Settings is open isn't taken for an edit")
    func syncWhileOpenIsNotAnEdit() throws {
        let guide = try CoreDataTestHelpers.makeContext()
        #expect(AttendanceEmailLog.saveSettings(Self.emailSettings, role: .leadGuide, now: Self.earlier, in: guide))
        #expect(CoreDataTestHelpers.save(guide))
        let device = try AttendanceSettingsTestDevice(preferences: Self.emailSettings)

        // Settings is open: the guide types a new address for the email,
        // and starts on a ParentLocker address.
        var drafts = AttendanceSettingsDrafts()
        drafts.paused = AttendanceSettingsEdit(toAddresses: "front@school.org; nurse@school.org")
        drafts.site = "https://New.ParentLocker.com/sis"

        // Meanwhile his Mac picks ParentLocker, and it syncs in here.
        var fromMac = Self.emailSettings
        fromMac.sendMethod = .parentLocker
        #expect(AttendanceEmailLog.saveSettings(fromMac, role: .leadGuide, now: Self.earlier + 60, in: guide))
        #expect(CoreDataTestHelpers.save(guide))
        let synced = try #require(AttendanceEmailLog.settings(in: guide))
        #expect(AttendanceEmail.shownSettings(row: synced, preferences: device.preferences, isSampleClass: false)
            .sendMethod == .parentLocker)

        // Closing Settings writes what was typed, and only that.
        let edit = drafts.takeAll(shownSite: synced.parentLockerSite)
        #expect(edit.sendMethod == nil)
        #expect(AttendanceEmail.shareEdit(
            edit, in: guide, isSampleClass: false, device: device.settings, firstDownloadPending: false
        ))

        let shared = try #require(AttendanceEmailLog.settings(in: reader(for: guide)))
        #expect(shared.sendMethod == .parentLocker, "the Mac's choice stands")
        #expect(shared.parentLockerSite == "new.parentlocker.com")
        #expect(shared.toAddresses == "front@school.org, nurse@school.org")
        #expect(device.writtenKeys == [AttendanceEmailPrefs.toKey, AttendanceEmailPrefs.parentLockerSiteKey])
        #expect(device.written[AttendanceEmailPrefs.toKey] as? String == "front@school.org; nurse@school.org",
                "the preference keeps the addresses as typed")
        #expect(!AttendanceEmail.writePendingEdit(
            in: guide, isSampleClass: false, device: device.settings, firstDownloadPending: false
        ), "opening Settings again writes nothing")
    }

    @Test("The launch's settings never outrank the guide's row arriving after it")
    func launchSeedLosesToALaterRow() throws {
        let context = try CoreDataTestHelpers.makeContext()
        // A new device: the first download finished before the share's row came.
        #expect(AttendanceEmail.shareSettingsIfMissing(
            in: context, settings: Self.emailSettings, firstDownloadPending: false
        ))
        #expect(CoreDataTestHelpers.save(context))

        // The guide's row, written yesterday on his Mac, arrives.
        let arrived = CDAttendanceEmailSettings(context: context)
        arrived.isEnabled = false
        arrived.toAddresses = "office@school.org"
        arrived.sendMethodRaw = AttendanceSendMethod.parentLocker.rawValue
        arrived.parentLockerSite = "yyli.parentlocker.com"
        arrived.modifiedAt = Date().addingTimeInterval(-86_400)
        #expect(CoreDataTestHelpers.save(context))
        #expect(context.safeFetch(CDFetchRequest(CDAttendanceEmailSettings.self)).count == 2)

        #expect(AttendanceEmailLog.settings(in: context)?.sendMethod == .parentLocker)

        // The next edit keeps the guide's row, and only it.
        let device = try AttendanceSettingsTestDevice(preferences: Self.emailSettings)
        #expect(AttendanceEmail.shareEdit(
            AttendanceSettingsEdit(deadlineMinutes: 8 * 60 + 50),
            in: context, isSampleClass: false, device: device.settings, firstDownloadPending: false
        ))
        #expect(context.safeFetch(CDFetchRequest(CDAttendanceEmailSettings.self)).count == 1)
        #expect(AttendanceEmailLog.settings(in: context)?.sendMethod == .parentLocker)
    }

    @Test("The Sample Class changes its own row only: never the preferences or a pending write")
    func sampleClassNeverWritesThePreferences() throws {
        let sample = try CoreDataTestHelpers.makeContext()
        let device = try AttendanceSettingsTestDevice(preferences: Self.emailSettings)

        // Even while the guide's own class is still downloading.
        #expect(AttendanceEmail.shareEdit(
            AttendanceSettingsEdit(sendMethod: .parentLocker),
            in: sample, isSampleClass: true, device: device.settings, firstDownloadPending: true
        ))
        #expect(AttendanceEmailLog.settings(in: sample)?.sendMethod == .parentLocker)
        #expect(device.written.isEmpty)
        #expect(device.pending == nil)

        // A write the guide's own class owes is never put into the sample.
        let guide = try CoreDataTestHelpers.makeContext()
        #expect(!AttendanceEmail.shareEdit(
            AttendanceSettingsEdit(deadlineMinutes: 8 * 60), in: guide, isSampleClass: false,
            device: device.settings, firstDownloadPending: true
        ))
        #expect(device.pending != nil)
        #expect(!AttendanceEmail.writePendingEdit(
            in: sample, isSampleClass: true, device: device.settings, firstDownloadPending: false
        ))
        #expect(AttendanceEmailLog.settings(in: sample)?.deadlineMinutes == AttendanceEmailLog.defaultDeadlineMinutes)
        #expect(device.pending != nil, "kept for the guide's own class")
    }

    @Test("A write put off during a first download goes in only if the row hasn't changed since")
    func putOffWriteNeedsTheSameRow() throws {
        let guide = try CoreDataTestHelpers.makeContext()
        #expect(AttendanceEmailLog.saveSettings(Self.emailSettings, role: .leadGuide, now: Self.earlier, in: guide))
        #expect(CoreDataTestHelpers.save(guide))
        let device = try AttendanceSettingsTestDevice(preferences: Self.emailSettings)

        // Picked during a first download: the row waits, the preference doesn't.
        #expect(!AttendanceEmail.shareEdit(
            AttendanceSettingsEdit(sendMethod: .parentLocker),
            in: guide, isSampleClass: false, device: device.settings, firstDownloadPending: true
        ))
        #expect(AttendanceEmailLog.settings(in: guide)?.sendMethod == .email)
        #expect(device.written[AttendanceEmailPrefs.sendMethodKey] as? String == "parentLocker")
        #expect(device.pending?.edit == AttendanceSettingsEdit(sendMethod: .parentLocker))
        #expect(!AttendanceEmail.writePendingEdit(
            in: guide, isSampleClass: false, device: device.settings, firstDownloadPending: true
        ), "still downloading")

        // Settings opens once it's done, and nothing else wrote the row: it goes in.
        #expect(AttendanceEmail.writePendingEdit(
            in: guide, isSampleClass: false, device: device.settings, firstDownloadPending: false
        ))
        #expect(AttendanceEmailLog.settings(in: reader(for: guide))?.sendMethod == .parentLocker)
        #expect(device.pending == nil)

        // Put off again, but another device's edit lands first: that one stands.
        #expect(!AttendanceEmail.shareEdit(
            AttendanceSettingsEdit(deadlineMinutes: 8 * 60), in: guide, isSampleClass: false,
            device: device.settings, firstDownloadPending: true
        ))
        var fromMac = try #require(AttendanceEmailLog.settings(in: guide))
        fromMac.deadlineMinutes = 8 * 60 + 15
        #expect(AttendanceEmailLog.saveSettings(fromMac, role: .leadGuide, now: Date() + 60, in: guide))
        #expect(CoreDataTestHelpers.save(guide))
        #expect(!AttendanceEmail.writePendingEdit(
            in: guide, isSampleClass: false, device: device.settings, firstDownloadPending: false
        ))
        #expect(AttendanceEmailLog.settings(in: guide)?.deadlineMinutes == 8 * 60 + 15)
        #expect(device.pending == nil, "dropped")
    }

    @Test("A method picked in Settings is in the share at once; picking the email again turns it on")
    func pickedMethodIsSavedAtOnce() throws {
        let guide = try CoreDataTestHelpers.makeContext()
        #expect(AttendanceEmailLog.saveSettings(Self.emailSettings, role: .leadGuide, in: guide))
        #expect(CoreDataTestHelpers.save(guide))
        let device = try AttendanceSettingsTestDevice(preferences: Self.emailSettings)

        #expect(AttendanceEmail.shareEdit(
            AttendanceSettingsEdit(sendMethod: .parentLocker),
            in: guide, isSampleClass: false, device: device.settings, firstDownloadPending: false
        ))
        let picked = try #require(AttendanceEmailLog.settings(in: reader(for: guide)))
        #expect(picked.sendMethod == .parentLocker)
        #expect(!picked.isEnabled, "older Assistant builds stop offering the email")
        #expect(device.writtenKeys == [AttendanceEmailPrefs.sendMethodKey])

        #expect(AttendanceEmail.shareEdit(
            AttendanceSettingsEdit(sendMethod: .email),
            in: guide, isSampleClass: false, device: device.settings, firstDownloadPending: false
        ))
        let back = try #require(AttendanceEmailLog.settings(in: reader(for: guide)))
        #expect(back.sendMethod == .email)
        #expect(back.isEnabled, "as the guide's own switch says")
        #expect(back.canSend)
    }

    @Test("An assistant's notebook never writes the row or a pending write")
    func assistantsNotebookNeverWrites() throws {
        let context = try CoreDataTestHelpers.makeContext()
        #expect(AttendanceEmailLog.saveSettings(Self.emailSettings, role: .leadGuide, in: context))
        CoreDataTestHelpers.seedClassroomMembership(in: context, role: .assistant)
        #expect(CoreDataTestHelpers.save(context))
        let device = try AttendanceSettingsTestDevice(preferences: Self.emailSettings)

        #expect(!AttendanceEmail.shareEdit(
            AttendanceSettingsEdit(sendMethod: .parentLocker),
            in: context, isSampleClass: false, device: device.settings, firstDownloadPending: true
        ))
        #expect(device.pending == nil)
        #expect(!AttendanceEmail.shareEdit(
            AttendanceSettingsEdit(sendMethod: .parentLocker),
            in: context, isSampleClass: false, device: device.settings, firstDownloadPending: false
        ))
        #expect(AttendanceEmailLog.settings(in: context)?.sendMethod == .email)
    }

    // MARK: - L3: the address

    @Test("The ParentLocker address goes in on Return or closing, never after a pause")
    func typedAddressWaitsForReturnOrClose() {
        var drafts = AttendanceSettingsDrafts()
        drafts.site = "yyli.parentl"
        drafts.paused = AttendanceSettingsEdit(deadlineMinutes: 8 * 60 + 40)

        let paused = drafts.takePaused()
        #expect(paused == AttendanceSettingsEdit(deadlineMinutes: 8 * 60 + 40))
        #expect(paused.parentLockerSite == nil, "a half-typed host never goes in")
        #expect(drafts.site == "yyli.parentl")

        drafts.site = " https://YYLI.ParentLocker.com/sis "
        #expect(drafts.takeSite(shown: "yyli.parentlocker.com").isEmpty, "the same address writes nothing")
        #expect(drafts.site == nil)

        drafts.site = "school.parentlocker.com"
        #expect(drafts.takeAll(shownSite: "yyli.parentlocker.com")
            == AttendanceSettingsEdit(parentLockerSite: "school.parentlocker.com"))
        #expect(drafts == AttendanceSettingsDrafts())
    }

    // MARK: - M9: the sign-in row

    @Test("The sign-in row asks for a sign-in again whenever ParentLocker needs one")
    func signInRowSaysSignInAgain() {
        typealias Row = AttendanceParentLockerSettings
        #expect(Row.signInTitle(isSignedIn: true, needsSignIn: true) == "Sign in again")
        #expect(Row.signInButtonTitle(needsSignIn: true) == "Sign In…")
        #expect(Row.signInTitle(isSignedIn: false, needsSignIn: true) == "Not signed in")
        #expect(Row.signInTitle(isSignedIn: true, needsSignIn: false) == "Signed in")
        #expect(Row.signInButtonTitle(needsSignIn: false) == "Sign Out…")
    }
}
