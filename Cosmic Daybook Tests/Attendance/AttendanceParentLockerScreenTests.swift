import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// The attendance screen with ParentLocker picked (bug check 2026-10-13):
/// it reads the method where the sync, the reminder, MCP and the assistants
/// do (C1), and never records a ParentLocker send for a day that hasn't come (C2).
@Suite("Attendance screen and ParentLocker")
@MainActor
struct AttendanceParentLockerScreenTests {

    private static let emailSettings = AttendanceEmailLog.Settings(
        isEnabled: true,
        toAddresses: "office@school.org",
        nameOrder: .firstLast,
        groupByLevel: false
    )

    // MARK: - C1: the method comes from the shared row

    @Test("The screen's method is the shared row's, and email before there is one")
    func methodComesFromTheSharedRow() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        #expect(AttendanceExpandedView.sendMethod(in: ctx) == .email, "no row yet")

        var picked = Self.emailSettings
        picked.sendMethod = .parentLocker
        #expect(AttendanceEmailLog.saveSettings(picked, role: .leadGuide, in: ctx))
        #expect(CoreDataTestHelpers.save(ctx))
        #expect(AttendanceExpandedView.sendMethod(in: ctx) == .parentLocker)

        #expect(AttendanceEmailLog.saveSettings(Self.emailSettings, role: .leadGuide, in: ctx))
        #expect(CoreDataTestHelpers.save(ctx))
        #expect(AttendanceExpandedView.sendMethod(in: ctx) == .email)
    }

    @Test("Settings writes a method change to the shared row at once, and saves it")
    func settingsSharesTheMethodAtOnce() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let guide = stack.viewContext
        var picked = Self.emailSettings
        picked.sendMethod = .parentLocker

        #expect(AttendanceEmailSettingsView.shareSettingsNow(in: guide, settings: picked, firstDownloadPending: false))

        // Saved, not just changed: another context on the store sees it.
        let other = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        other.persistentStoreCoordinator = guide.persistentStoreCoordinator
        #expect(AttendanceEmailLog.settings(in: other)?.sendMethod == .parentLocker)
        #expect(!AttendanceEmailSettingsView.shareSettingsNow(in: guide, settings: picked, firstDownloadPending: false),
                "nothing to write the second time")
        #expect(!AttendanceEmailSettingsView.shareSettingsNow(
            in: guide, settings: Self.emailSettings, firstDownloadPending: true
        ), "not during a first download")
        #expect(AttendanceEmailLog.settings(in: other)?.sendMethod == .parentLocker)
    }

    // Review of the bug-check fixes: a method change whose write was skipped
    // (during a first download, say) left the share on the old method for good.
    @Test("Opening Settings puts the share's method and site right, keeping its other fields")
    func settingsRepairsTheSharedMethod() throws {
        typealias Screen = AttendanceEmailSettingsView
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let guide = stack.viewContext
        var newer = Self.emailSettings
        newer.toAddresses = "new-office@school.org"
        #expect(AttendanceEmailLog.saveSettings(newer, role: .leadGuide, in: guide))
        #expect(CoreDataTestHelpers.save(guide))

        // This device's preferences: ParentLocker, and older recipients.
        var preferences = Self.emailSettings
        preferences.toAddresses = "old-office@school.org"
        preferences.sendMethod = .parentLocker
        preferences.parentLockerSite = "https://School.ParentLocker.com/sis"
        #expect(!Screen.repairSharedMethodNow(
            in: guide, settings: preferences, firstDownloadPending: true
        ), "not during a first download")
        #expect(AttendanceEmailLog.settings(in: guide)?.sendMethod == .email)

        #expect(Screen.repairSharedMethodNow(in: guide, settings: preferences, firstDownloadPending: false))
        let other = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        other.persistentStoreCoordinator = guide.persistentStoreCoordinator
        let row = try #require(AttendanceEmailLog.settings(in: other))
        #expect(row.sendMethod == .parentLocker)
        #expect(row.parentLockerSite == "school.parentlocker.com")
        #expect(!row.isEnabled, "with ParentLocker picked the email reads as off")
        #expect(row.toAddresses == "new-office@school.org", "the row's other fields stay")
        #expect(!Screen.repairSharedMethodNow(in: guide, settings: preferences, firstDownloadPending: false),
                "nothing to put right the second time")

        // Back to email: the email's switch comes from the preferences too.
        preferences.sendMethod = .email
        #expect(Screen.repairSharedMethodNow(in: guide, settings: preferences, firstDownloadPending: false))
        #expect(AttendanceEmailLog.settings(in: guide)?.sendMethod == .email)
        #expect(AttendanceEmailLog.settings(in: guide)?.isEnabled == true)
    }

    @Test("An assistant's notebook never puts the share's method right")
    func assistantNeverRepairs() throws {
        let context = try CoreDataTestHelpers.makeContext()
        #expect(AttendanceEmailLog.saveSettings(Self.emailSettings, role: .leadGuide, in: context))
        CoreDataTestHelpers.seedClassroomMembership(in: context, role: .assistant)
        #expect(CoreDataTestHelpers.save(context))
        var preferences = Self.emailSettings
        preferences.sendMethod = .parentLocker
        #expect(!AttendanceEmail.repairSharedMethod(in: context, settings: preferences, firstDownloadPending: false))
        #expect(AttendanceEmailLog.settings(in: context)?.sendMethod == .email)
    }

    // MARK: - C2: Mark as Sent on a future day

    @Test("Mark as Sent refuses a ParentLocker send for a day that hasn't come")
    func markAsSentRefusesTheFuture() throws {
        let today = try CoreDataTestHelpers.day("2026-10-13").addingTimeInterval(10 * 3_600)
        let tomorrow = try CoreDataTestHelpers.day("2026-10-14")
        let yesterday = try CoreDataTestHelpers.day("2026-10-12")
        typealias View = AttendanceExpandedView

        let future = try #require(View.parentLockerMarkRefusal(on: tomorrow, now: today, allowsSaving: true))
        #expect(!future.isEmpty)
        #expect(View.parentLockerMarkRefusal(on: today, now: today, allowsSaving: true) == nil)
        #expect(View.parentLockerMarkRefusal(on: yesterday, now: today, allowsSaving: true) == nil)
        #expect(View.parentLockerMarkRefusal(on: yesterday, now: today, allowsSaving: false)
            == "This test copy of the app doesn't record ParentLocker sends.")
    }
}
