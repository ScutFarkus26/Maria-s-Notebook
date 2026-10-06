import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Data model hunt 2026-10-05, #25. Every launch on each of the guide's
// devices copied that device's email preferences into the shared settings
// row. iCloud brings preferences to a device in its own time, so a device
// that hadn't caught up yet put back the old recipients over an edit made on
// another device, and the assistants' email went to the old addresses. The
// launch now writes the row only when the share has none; edits come from
// the settings screen.

@Suite("The launch writes the email settings only when the share has none")
@MainActor
struct AttendanceEmailSettingsLaunchTests {

    private static let newer = AttendanceEmailLog.Settings(
        isEnabled: true, toAddresses: "office@school.org", nameOrder: .lastFirst, groupByLevel: true,
        deadlineMinutes: 8 * 60 + 45
    )
    private static let staleOnThisDevice = AttendanceEmailLog.Settings(
        isEnabled: true, toAddresses: "old-office@school.org", nameOrder: .firstLast, groupByLevel: false
    )

    @Test("A row already in the share is left as it is, whatever this device's preferences say")
    func existingRowLeftAlone() throws {
        let context = try CoreDataTestHelpers.makeContext()
        #expect(AttendanceEmailLog.saveSettings(Self.newer, role: .leadGuide, in: context))
        #expect(CoreDataTestHelpers.save(context))

        let wrote = AttendanceEmail.shareSettingsIfMissing(
            in: context, settings: Self.staleOnThisDevice, firstDownloadPending: false
        )

        #expect(!wrote)
        #expect(!context.hasChanges)
        #expect(AttendanceEmailLog.settings(in: context) == Self.newer)
    }

    @Test("With no row yet, the launch writes this device's settings once")
    func missingRowWrittenOnce() throws {
        let context = try CoreDataTestHelpers.makeContext()

        #expect(AttendanceEmail.shareSettingsIfMissing(in: context, settings: Self.newer, firstDownloadPending: false))
        #expect(CoreDataTestHelpers.save(context))
        #expect(AttendanceEmailLog.settings(in: context) == Self.newer)

        #expect(!AttendanceEmail.shareSettingsIfMissing(
            in: context, settings: Self.staleOnThisDevice, firstDownloadPending: false
        ))
        #expect(AttendanceEmailLog.settings(in: context) == Self.newer)
    }

    @Test("Nothing is written during the first download or on an assistant's notebook")
    func noWriteWhileDownloadingOrAsAssistant() throws {
        let context = try CoreDataTestHelpers.makeContext()
        #expect(!AttendanceEmail.shareSettingsIfMissing(in: context, settings: Self.newer, firstDownloadPending: true))

        CoreDataTestHelpers.seedClassroomMembership(in: context, role: .assistant)
        #expect(CoreDataTestHelpers.save(context))
        #expect(!AttendanceEmail.shareSettingsIfMissing(in: context, settings: Self.newer, firstDownloadPending: false))
        #expect(AttendanceEmailLog.settings(in: context) == nil)
    }
}
