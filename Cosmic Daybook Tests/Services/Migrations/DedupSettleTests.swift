import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Review of the 2026-10-05 fixes: folding copies one child's winning mark onto
// the copy kept by identity and sends it to iCloud. A device that hadn't yet
// imported a newer mark made elsewhere would send its older idea of the day
// and overwrite it. So a day's copies are folded only once they have settled:
// nothing changed in the last ten minutes, and an import that began after the
// newest change has finished into their store.

@Suite("Attendance copies fold once settled")
@MainActor
struct DedupSettleTests {

    private let studentID = "8D3F1C2A-0000-0000-0000-000000000042"
    private let day = AppCalendar.startOfDay(Date(timeIntervalSinceReferenceDate: 780_000_000))

    private func at(_ minutes: Double) -> Date {
        day.addingTimeInterval(8 * 3600 + minutes * 60)
    }

    /// Two copies of one child's day, last changed at minutes `first` and `second` past 8:00.
    private func copies(changedAt first: Double, _ second: Double) throws -> NSManagedObjectContext {
        let context = try CoreDataTestHelpers.makeContext()
        for (status, minute) in [("present", first), ("absent", second)] {
            let record = CDAttendanceRecord(context: context)
            record.id = UUID()
            record.studentID = studentID
            record.date = day
            record.statusRaw = status
            record.modifiedAt = at(minute)
        }
        #expect(CoreDataTestHelpers.save(context))
        return context
    }

    private func records(in context: NSManagedObjectContext) -> [CDAttendanceRecord] {
        context.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).filter { !$0.isDeleted }
    }

    @Test("A day changed in the last ten minutes waits")
    func recentChangeWaits() throws {
        let context = try copies(changedAt: 0, 20)
        let importStart = at(25)
        let lookup: @Sendable (String) -> Date? = { _ in importStart }
        let settling = DedupSyncState.$lastImportOverride.withValue(lookup) {
            DedupSyncState.stillSettling(records(in: context), container: nil, now: at(25))
        }
        #expect(settling)
    }

    @Test("A day with no import begun since its newest change waits")
    func noImportSinceWaits() throws {
        let context = try copies(changedAt: 0, 20)
        let importStart = at(15)
        let lookup: @Sendable (String) -> Date? = { _ in importStart }
        let settling = DedupSyncState.$lastImportOverride.withValue(lookup) {
            DedupSyncState.stillSettling(records(in: context), container: nil, now: at(90))
        }
        #expect(settling)
    }

    @Test("A day left alone, with an import since, is folded")
    func settledDayFolds() throws {
        let context = try copies(changedAt: 0, 20)
        let importStart = at(30)
        let lookup: @Sendable (String) -> Date? = { _ in importStart }
        let settling = DedupSyncState.$lastImportOverride.withValue(lookup) {
            DedupSyncState.stillSettling(records(in: context), container: nil, now: at(90))
        }
        #expect(!settling)
    }

    @Test("The cleanup leaves an unsettled day's copies in place")
    func cleanupWaitsForSettling() throws {
        let context = try copies(changedAt: 0, 20)
        let lookup: @Sendable (String) -> Date? = { _ in nil }
        let removed = DedupSyncState.$lastImportOverride.withValue(lookup) {
            DataCleanupService.deduplicateAttendanceRecordsStrong(using: context)
        }
        #expect(removed == 0)
        #expect(records(in: context).count == 2)
    }
}
