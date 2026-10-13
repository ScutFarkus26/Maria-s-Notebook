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
