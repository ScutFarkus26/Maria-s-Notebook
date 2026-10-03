import Foundation
import CoreData
import OSLog

/// Locked attendance days: read by everyone, set only by the lead guide.
///
/// A day is locked while at least one `AttendanceDayLock` row exists for it.
/// The rows live in the classroom share, so the assistant's app sees the same
/// locks the guide set and `CDAttendanceStore` refuses edits on a locked day
/// for everyone. Two devices locking the same day leave two rows, which is
/// harmless: unlocking deletes every row for the day.
///
/// Until schema 9 a lock was the `Attendance.locked.<yyyy-MM-dd>` iCloud
/// key-value setting, which only the guide's own devices could read.
/// `migrateLegacyKeys` turns those into rows (once per device, and after a
/// restore of an older backup); the keys themselves are left alone, because
/// a Development build still reads them.
nonisolated enum AttendanceDayLocks {

    static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "CosmicDaybook",
        category: "AttendanceDayLocks"
    )

    /// The old key-value setting's prefix; the day follows as `yyyy-MM-dd`.
    static let legacyKeyPrefix = "Attendance.locked."

    // MARK: - Reading

    static func isLocked(_ date: Date, in context: NSManagedObjectContext) -> Bool {
        let request = CDFetchRequest(CDAttendanceDayLock.self)
        request.predicate = NSPredicate(format: "date == %@", AppCalendar.startOfDay(date) as NSDate)
        request.fetchLimit = 1
        return ((try? context.count(for: request)) ?? 0) > 0
    }

    // MARK: - Writing

    /// Locks or unlocks `date`. Only the lead guide may; returns whether
    /// anything changed. The caller saves.
    @discardableResult
    static func setLocked(
        _ locked: Bool,
        for date: Date,
        role: CDClassroomMembership.ClassroomRole,
        lockedByID: String? = nil,
        in context: NSManagedObjectContext
    ) -> Bool {
        guard role == .leadGuide else { return false }
        let day = AppCalendar.startOfDay(date)
        let request = CDFetchRequest(CDAttendanceDayLock.self)
        request.predicate = NSPredicate(format: "date == %@", day as NSDate)
        let existing = context.safeFetch(request)
        if locked {
            guard existing.isEmpty else { return false }
            let lock = CDAttendanceDayLock(context: context)
            lock.date = day
            lock.lockedByID = lockedByID
            // The guide's classroom records live in the private store and
            // join the share from there (`SharedStoreOrphanGuard`).
            if let store = privateStore(of: context) { context.assign(lock, to: store) }
            return true
        }
        guard !existing.isEmpty else { return false }
        existing.forEach(context.delete)
        return true
    }

    private static func privateStore(of context: NSManagedObjectContext) -> NSPersistentStore? {
        guard let stores = context.persistentStoreCoordinator?.persistentStores, stores.count > 1 else { return nil }
        return stores.first { $0.configurationName == CoreDataStack.privateConfiguration }
    }
}
