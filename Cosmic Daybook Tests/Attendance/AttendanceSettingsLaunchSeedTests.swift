import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The review of the afternoon fixes, H1's last gap: a device whose only
// settings row is the launch's own (its preferences as they stood, dated
// long ago so the guide's row arriving later wins) put an edit onto it
// stamped now, and so outranked the guide's row with its stale defaults.
// The edit now waits, as one made during a first download does.

extension AttendanceSettingsSharedRowTests {

    @Test("An edit on a device holding only the launch's own settings waits, and never outranks the guide's row")
    func editOnTheLaunchSeedWaits() throws {
        let context = try CoreDataTestHelpers.makeContext()
        // A new device: the first download finished before the share's row came.
        #expect(AttendanceEmail.shareSettingsIfMissing(
            in: context, settings: Self.emailSettings, firstDownloadPending: false
        ))
        #expect(CoreDataTestHelpers.save(context))
        let device = try AttendanceSettingsTestDevice(preferences: Self.emailSettings)

        // A new due time here waits: the guide's own row may be on its way.
        #expect(!AttendanceEmail.shareEdit(
            AttendanceSettingsEdit(deadlineMinutes: 8 * 60 + 50),
            in: context, isSampleClass: false, device: device.settings, firstDownloadPending: false
        ))
        #expect(device.pending?.edit == AttendanceSettingsEdit(deadlineMinutes: 8 * 60 + 50))
        #expect(device.written[AttendanceEmailPrefs.deadlineKey] as? Int == 8 * 60 + 50)

        // The guide's row, written yesterday on his Mac, arrives: two rows.
        let arrived = CDAttendanceEmailSettings(context: context)
        arrived.isEnabled = false
        arrived.toAddresses = "office@school.org"
        arrived.sendMethodRaw = AttendanceSendMethod.parentLocker.rawValue
        arrived.parentLockerSite = "yyli.parentlocker.com"
        arrived.modifiedAt = Date().addingTimeInterval(-86_400)
        #expect(CoreDataTestHelpers.save(context))
        #expect(context.safeFetch(CDFetchRequest(CDAttendanceEmailSettings.self)).count == 2)
        #expect(AttendanceEmailLog.settings(in: reader(for: context))?.sendMethod == .parentLocker)

        // Settings opens again: the row changed since, so the guide's stands.
        #expect(!AttendanceEmail.writePendingEdit(
            in: context, isSampleClass: false, device: device.settings, firstDownloadPending: false
        ))
        #expect(AttendanceEmailLog.settings(in: reader(for: context))?.sendMethod == .parentLocker)
        #expect(device.pending == nil)
    }

    @Test("With only the launch's own row, Settings shows the edit, and it goes in as Settings opens again")
    func launchSeedEditGoesInLater() throws {
        let context = try CoreDataTestHelpers.makeContext()
        #expect(AttendanceEmail.shareSettingsIfMissing(
            in: context, settings: Self.emailSettings, firstDownloadPending: false
        ))
        #expect(CoreDataTestHelpers.save(context))
        #expect(AttendanceEmail.shownRow(in: context, isSampleClass: false) == nil, "this device's own settings show")
        #expect(AttendanceEmail.shownRow(in: context, isSampleClass: true) != nil, "the Sample Class shows its row")
        let device = try AttendanceSettingsTestDevice(preferences: Self.emailSettings)
        #expect(!AttendanceEmail.shareEdit(
            AttendanceSettingsEdit(sendMethod: .parentLocker),
            in: context, isSampleClass: false, device: device.settings, firstDownloadPending: false
        ))

        // No row of the guide's came: the edit goes in as Settings opens again.
        #expect(AttendanceEmail.writePendingEdit(
            in: context, isSampleClass: false, device: device.settings, firstDownloadPending: false
        ))
        #expect(AttendanceEmailLog.settings(in: reader(for: context))?.sendMethod == .parentLocker)
        #expect(AttendanceSettingsPendingWrite.rowStamp(in: context)?.isLaunchSeed == false)
        #expect(AttendanceEmail.shownRow(in: context, isSampleClass: false)?.sendMethod == .parentLocker)
    }
}
