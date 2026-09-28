import Foundation
import CoreData
import Testing
@testable import CosmicDaybook

/// Locked attendance days are shared records (schema 9): everyone reads them,
/// only the lead guide sets them, and a locked day takes no edits from anyone.
@Suite("Attendance day locks")
@MainActor
struct AttendanceDayLockTests {

    private func day(_ iso: String) throws -> Date {
        try CoreDataTestHelpers.day(iso)
    }

    @Test("Lock and unlock a day; unlocking removes every row for it")
    func lockAndUnlock() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let monday = try day("2026-10-12")
        #expect(!AttendanceDayLocks.isLocked(monday, in: ctx))

        let nineAM = monday.addingTimeInterval(9 * 3_600)
        #expect(AttendanceDayLocks.setLocked(true, for: nineAM, role: .leadGuide, in: ctx))
        #expect(AttendanceDayLocks.isLocked(monday, in: ctx))
        #expect(!AttendanceDayLocks.setLocked(true, for: monday, role: .leadGuide, in: ctx), "already locked")
        #expect(!AttendanceDayLocks.isLocked(try day("2026-10-13"), in: ctx))

        // A second device's lock for the same day, synced in.
        let twin = CDAttendanceDayLock(context: ctx)
        twin.date = monday
        #expect(CoreDataTestHelpers.save(ctx))

        #expect(AttendanceDayLocks.setLocked(false, for: monday, role: .leadGuide, in: ctx))
        #expect(CoreDataTestHelpers.save(ctx))
        #expect(!AttendanceDayLocks.isLocked(monday, in: ctx))
        #expect(ctx.safeFetch(CDFetchRequest(CDAttendanceDayLock.self)).isEmpty)
    }

    @Test("Only the lead guide locks or unlocks")
    func onlyTheGuideLocks() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let monday = try day("2026-10-12")
        #expect(!AttendanceDayLocks.setLocked(true, for: monday, role: .assistant, in: ctx))
        #expect(!AttendanceDayLocks.isLocked(monday, in: ctx))
        AttendanceDayLocks.setLocked(true, for: monday, role: .leadGuide, in: ctx)
        #expect(!AttendanceDayLocks.setLocked(false, for: monday, role: .assistant, in: ctx))
        #expect(AttendanceDayLocks.isLocked(monday, in: ctx))
    }

    @Test("A locked day takes no edits from the guide or an assistant", arguments: [
        CDClassroomMembership.ClassroomRole.leadGuide, .assistant
    ])
    func lockedDayRefusesEdits(role: CDClassroomMembership.ClassroomRole) throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let monday = try day("2026-10-12")
        let student = CoreDataTestHelpers.seedStudent(in: ctx)
        let store = CDAttendanceStore(context: ctx, role: role)
        let record = try #require(try store.ensureRecord(for: student, on: monday))
        #expect(store.updateStatus(record, to: .present))

        AttendanceDayLocks.setLocked(true, for: monday, role: .leadGuide, in: ctx)
        #expect(store.isLocked(monday))
        #expect(!store.updateStatus(record, to: .absent))
        #expect(!store.updateNote(record, to: "late bus"))
        #expect(try store.ensureRecord(for: CoreDataTestHelpers.seedStudent(in: ctx), on: monday) == nil)
        #expect(try store.markAllPresent(for: monday, students: [student]).isEmpty)
        #expect(record.status == .present)

        // Another day is unaffected.
        #expect(try store.ensureRecord(for: student, on: try day("2026-10-13")) != nil)
    }

    @Test("Old key-value locks become records once, and only the guide's")
    func legacyKeysCarryOver() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let keys: [String: Any] = [
            "Attendance.locked.2026-09-14": true,
            "Attendance.locked.2026-09-15": NSNumber(value: true),
            "Attendance.locked.2026-09-16": false,
            "Attendance.locked.not-a-day": true,
            "Attendance.email.enabled": true
        ]
        #expect(AttendanceDayLocks.legacyLockedDays(in: keys) == [try day("2026-09-14"), try day("2026-09-15")])
        #expect(AttendanceDayLocks.migrateLegacyKeys(keys, role: .assistant, in: ctx) == 0)
        #expect(AttendanceDayLocks.migrateLegacyKeys(keys, role: .leadGuide, in: ctx) == 2)
        #expect(AttendanceDayLocks.migrateLegacyKeys(keys, role: .leadGuide, in: ctx) == 0, "idempotent")
        #expect(AttendanceDayLocks.isLocked(try day("2026-09-15"), in: ctx))
        #expect(!AttendanceDayLocks.isLocked(try day("2026-09-16"), in: ctx))
    }

    @Test("Only a pre-v30 backup's old lock settings become locks on restore")
    func restoreCarriesOldLocksOnlyFromOldBackups() throws {
        let ctx = try CoreDataTestHelpers.makeContext()
        let prefs = PreferencesDTO(values: ["Attendance.locked.2026-09-14": .bool(true)])
        // A v30 backup carries lock records; its old key may name a day
        // unlocked since, which must stay unlocked.
        AttendanceDayLocks.carryOverRestoredLocks(prefs, formatVersion: 30, into: ctx)
        #expect(!AttendanceDayLocks.isLocked(try day("2026-09-14"), in: ctx))
        AttendanceDayLocks.carryOverRestoredLocks(prefs, formatVersion: 29, into: ctx)
        #expect(AttendanceDayLocks.isLocked(try day("2026-09-14"), in: ctx))
    }

    @Test("Unlocking names the old setting it clears")
    func legacyKeyForDay() throws {
        #expect(AttendanceDayLocks.legacyKey(for: try day("2026-09-14").addingTimeInterval(3_600))
            == "Attendance.locked.2026-09-14")
    }

    @Test("A restored backup's lock preferences are read as old locks")
    func restoredPreferencesCarryLocks() {
        let prefs = PreferencesDTO(values: [
            "Attendance.locked.2026-09-14": .bool(true),
            "Attendance.locked.2026-09-15": .bool(false),
            "School.year": .int(2026)
        ])
        let locks = AttendanceDayLocks.legacyLocks(in: prefs)
        #expect(Set(locks.keys) == ["Attendance.locked.2026-09-14", "Attendance.locked.2026-09-15"])
        #expect(AttendanceDayLocks.legacyLockedDays(in: locks).count == 1)
    }
}
