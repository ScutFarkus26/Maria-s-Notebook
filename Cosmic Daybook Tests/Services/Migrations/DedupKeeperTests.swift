import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-05 (#1, #40, #41, #42): every device runs the duplicate
// cleanup on its own, and the copy it kept was chosen by content: the latest
// mark, the active enrollment, the promoted plan. Two devices that had seen
// different edits could each keep a different copy and delete the other, and
// both deletes synced. The copy kept is now chosen by identity (the id string
// first), the same on every device at every sync state, and the winning
// content is copied onto it.

@Suite("Dedup keepers by identity")
@MainActor
struct DedupKeeperTests {

    private let low = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let high = UUID(uuidString: "FFFFFFFF-0000-0000-0000-000000000001")!
    private let studentID = "8D3F1C2A-0000-0000-0000-000000000042"
    private let day = AppCalendar.startOfDay(Date(timeIntervalSinceReferenceDate: 780_000_000))

    private func minute(_ value: Double) -> Date {
        day.addingTimeInterval(8 * 3600 + value * 60)
    }

    /// One copy of the child's day: its id, raw status and the minute past
    /// 8:00 it was last changed.
    private struct Copy {
        let id: UUID
        let statusRaw: String
        let modified: Double

        init(_ id: UUID, _ statusRaw: String, _ modified: Double) {
            self.id = id
            self.statusRaw = statusRaw
            self.modified = modified
        }
    }

    /// One device's copies of one child's day, saved.
    private func deviceView(_ copies: [Copy]) throws -> NSManagedObjectContext {
        let context = try CoreDataTestHelpers.makeContext()
        for copy in copies {
            let record = CDAttendanceRecord(context: context)
            record.id = copy.id
            record.studentID = studentID
            record.date = day
            record.statusRaw = copy.statusRaw
            record.modifiedAt = minute(copy.modified)
        }
        #expect(CoreDataTestHelpers.save(context))
        return context
    }

    private func records(in context: NSManagedObjectContext) -> [CDAttendanceRecord] {
        context.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).filter { !$0.isDeleted }
    }

    // MARK: - Attendance (#1)

    @Test("Two devices that have seen different edits keep the same copy")
    func devicesAgreeOnTheKeptCopy() throws {
        // Device A hasn't yet seen the absence an assistant marked on the
        // high-id copy at 8:20; the guide's Mac (G) has.
        let deviceA = try deviceView([Copy(low, "present", 10), Copy(high, "unmarked", 5)])
        let deviceG = try deviceView([Copy(low, "present", 10), Copy(high, "absent", 20)])

        #expect(DataCleanupService.deduplicateAttendanceRecordsStrong(using: deviceA) == 1)
        #expect(DataCleanupService.deduplicateAttendanceRecordsStrong(using: deviceG) == 1)

        // Both deleted the same copy, so one survives everywhere.
        #expect(records(in: deviceA).map(\.id) == [low])
        #expect(records(in: deviceG).map(\.id) == [low])
        // G's newer mark rides onto the kept copy, so A converges when it syncs.
        let kept = try #require(records(in: deviceG).first)
        #expect(kept.status == .absent)
        #expect(kept.modifiedAt == minute(20))
    }

    @Test("An older mark moves onto a newer unmarked kept copy without lowering its modifiedAt")
    func olderMarkKeepsTheNewerStamp() throws {
        // The guide planned a pickup on her own unmarked copy at 8:30; the
        // assistant's present mark from 8:10 is on the other copy.
        let context = try deviceView([Copy(low, "unmarked", 30), Copy(high, "present", 10)])
        let pickup = minute(330)
        let planned = try #require(records(in: context).first { $0.id == low })
        planned.leavesAt = pickup
        #expect(CoreDataTestHelpers.save(context))

        #expect(DataCleanupService.deduplicateAttendanceRecordsStrong(using: context) == 1)

        let kept = try #require(records(in: context).first)
        #expect(records(in: context).count == 1)
        #expect(kept.id == low)
        #expect(kept.status == .present)
        #expect(kept.modifiedAt == minute(30))
        #expect(kept.leavesAt == pickup)
    }

    @Test("A copy not yet in iCloud on the device that made it is kept or dropped as on every other device")
    func unsentCopyDoesNotChangeTheKeeper() throws {
        // The high-id copy was made on device A and hasn't gone up yet, so A
        // sees no record for it; on G it has one, and its record name sorts
        // first. Neither ordering may follow the record names.
        let deviceA = try deviceView([Copy(low, "present", 10), Copy(high, "present", 10)])
        let deviceG = try deviceView([Copy(low, "present", 10), Copy(high, "present", 10)])
        let highOnA = try #require(records(in: deviceA).first { $0.id == high }).objectID
        let lowOnG = try #require(records(in: deviceG).first { $0.id == low }).objectID

        let namesOnA: @Sendable (NSManagedObjectID) -> String? = { $0 == highOnA ? nil : "B-record" }
        let namesOnG: @Sendable (NSManagedObjectID) -> String? = { $0 == lowOnG ? "B-record" : "A-record" }
        let removedOnA = DedupSyncState.$recordNameOverride.withValue(namesOnA) {
            DataCleanupService.deduplicateAttendanceRecordsStrong(using: deviceA)
        }
        let removedOnG = DedupSyncState.$recordNameOverride.withValue(namesOnG) {
            DataCleanupService.deduplicateAttendanceRecordsStrong(using: deviceG)
        }

        #expect(removedOnA == 1 && removedOnG == 1)
        #expect(records(in: deviceA).map(\.id) == [low])
        #expect(records(in: deviceG).map(\.id) == [low])
    }

    @Test("A newer mark of the same kind replaces the kept copy's, with its time")
    func newerMarkReplacesTheKeptOne() throws {
        let context = try deviceView([Copy(low, "present", 10), Copy(high, "tardy", 25)])

        #expect(DataCleanupService.deduplicateAttendanceRecordsStrong(using: context) == 1)

        let kept = try #require(records(in: context).first)
        #expect(kept.id == low)
        #expect(kept.status == .tardy)
        #expect(kept.modifiedAt == minute(25))
    }

    // MARK: - Marks a build doesn't know (#42)

    @Test("A status this build doesn't know still counts as a mark")
    func unknownStatusIsAMark() throws {
        let context = try deviceView([Copy(low, "unmarked", 30), Copy(high, "excusedVisit", 10)])
        let rows = records(in: context)
        let unknown = try #require(rows.first { $0.id == high })
        let unmarked = try #require(rows.first { $0.id == low })

        // The read side shows the newer build's mark, not the blank copy.
        #expect(AttendanceDeduplication.wins(unknown, over: unmarked))
        #expect(!AttendanceDeduplication.wins(unmarked, over: unknown))

        // And the cleanup keeps it, raw, rather than reading it as unmarked.
        #expect(DataCleanupService.deduplicateAttendanceRecordsStrong(using: context) == 1)
        let kept = try #require(records(in: context).first)
        #expect(kept.statusRaw == "excusedVisit")
    }

    // MARK: - Same-id copies, to the millisecond (#41)

    @Test("Creation times within one millisecond are a tie, settled the same way everywhere")
    func createdAtComparedToTheMillisecond() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let shared = UUID()
        let first = CoreDataTestHelpers.seedNote(in: context, body: "Bead chains")
        let second = CoreDataTestHelpers.seedNote(in: context, body: "Bead chains")
        first.id = shared
        second.id = shared
        #expect(CoreDataTestHelpers.save(context))
        let byURI = [first, second].sorted {
            $0.objectID.uriRepresentation().absoluteString < $1.objectID.uriRepresentation().absoluteString
        }
        let (lowerURI, higherURI) = (byURI[0], byURI[1])

        // CloudKit keeps whole milliseconds: the copy that came down reads
        // .123, the device that made it still holds .1234.
        let instant = Date(timeIntervalSince1970: 1_790_000_000.123)
        higherURI.createdAt = instant
        lowerURI.createdAt = instant.addingTimeInterval(0.0004)

        #expect(DataCleanupService.precedesAsCanonical(lowerURI, higherURI, container: nil))
        #expect(!DataCleanupService.precedesAsCanonical(higherURI, lowerURI, container: nil))
    }

    // MARK: - Per-child keepers in the name merges (#40)

    private func sameNameLessons(in context: NSManagedObjectContext) throws -> (older: CDLesson, newer: CDLesson) {
        let older = CoreDataTestHelpers.seedLesson(in: context, name: "Rectangle", area: "Geometry", sequence: "Area")
        older.orderInSequence = 0
        let newer = CoreDataTestHelpers.seedLesson(in: context, name: "Rectangle", area: "Geometry", sequence: "Area")
        newer.orderInSequence = 5
        #expect(CoreDataTestHelpers.save(context))
        return (older, newer)
    }

    @Test("A child's two marks for one lesson keep the lower id, with the mastery folded onto it")
    func lessonMergeKeepsMarkByIdentity() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (older, newer) = try sameNameLessons(in: context)
        let mastered = minute(60)

        let earlier = CDLessonPresentation(context: context)
        earlier.id = high
        earlier.lessonID = try #require(older.id).uuidString
        earlier.studentID = studentID
        earlier.createdAt = mastered.addingTimeInterval(-86_400)
        let later = CDLessonPresentation(context: context)
        later.id = low
        later.lessonID = try #require(newer.id).uuidString
        later.studentID = studentID
        later.createdAt = mastered
        later.state = .proficient
        later.masteredAt = mastered
        #expect(CoreDataTestHelpers.save(context))

        #expect(DataCleanupService.mergeSameNameLessons(using: context) == 1)
        #expect(CoreDataTestHelpers.save(context))

        let marks = context.safeFetch(CDFetchRequest(CDLessonPresentation.self))
        let kept = try #require(marks.first)
        #expect(marks.count == 1)
        #expect(kept.id == low)
        #expect(kept.lessonID == older.id?.uuidString)
        #expect(kept.state == .proficient)
        #expect(kept.masteredAt == mastered)
    }

    @Test("A child's two plan entries for one lesson keep the lower id, promoted if either was")
    func lessonMergeKeepsPlanEntryByIdentity() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (older, newer) = try sameNameLessons(in: context)

        let planned = CDYearPlanEntry(context: context)
        planned.id = low
        planned.lessonID = try #require(older.id).uuidString
        planned.studentID = studentID
        planned.status = .planned
        let promoted = CDYearPlanEntry(context: context)
        promoted.id = high
        promoted.lessonID = try #require(newer.id).uuidString
        promoted.studentID = studentID
        promoted.status = .promoted
        promoted.promotedAssignmentID = "5A1B0000-0000-0000-0000-000000000007"
        #expect(CoreDataTestHelpers.save(context))

        #expect(DataCleanupService.mergeSameNameLessons(using: context) == 1)
        #expect(CoreDataTestHelpers.save(context))

        let entries = context.safeFetch(CDFetchRequest(CDYearPlanEntry.self))
        let kept = try #require(entries.first)
        #expect(entries.count == 1)
        #expect(kept.id == low)
        #expect(kept.status == .promoted)
        #expect(kept.promotedAssignmentID == "5A1B0000-0000-0000-0000-000000000007")
    }

    @Test("A child enrolled on both twin tracks keeps the lower-id enrollment, made active")
    func trackMergeKeepsEnrollmentByIdentity() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let olderTrack = CDTrackEntity(context: context)
        olderTrack.title = "Math — Laws"
        olderTrack.createdAt = try CoreDataTestHelpers.day("2026-01-10")
        let newerTrack = CDTrackEntity(context: context)
        newerTrack.title = "Math — Laws"
        newerTrack.createdAt = try CoreDataTestHelpers.day("2026-01-11")
        #expect(CoreDataTestHelpers.save(context))

        let retired = CDStudentTrackEnrollmentEntity(context: context)
        retired.id = low
        retired.studentID = studentID
        retired.trackID = try #require(olderTrack.id).uuidString
        retired.track = olderTrack
        retired.isActive = false
        retired.startedAt = try CoreDataTestHelpers.day("2026-01-11")
        let live = CDStudentTrackEnrollmentEntity(context: context)
        live.id = high
        live.studentID = studentID
        live.trackID = try #require(newerTrack.id).uuidString
        live.track = newerTrack
        live.isActive = true
        live.startedAt = try CoreDataTestHelpers.day("2026-02-01")
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Working steadily through the laws.")
        note.studentTrackEnrollmentID = high.uuidString
        #expect(CoreDataTestHelpers.save(context))

        #expect(DataCleanupService.mergeSameTitleTracks(using: context) == 1)
        #expect(CoreDataTestHelpers.save(context))

        let enrollments = context.safeFetch(CDFetchRequest(CDStudentTrackEnrollmentEntity.self))
        let kept = try #require(enrollments.first)
        #expect(enrollments.count == 1)
        #expect(kept.id == low)
        #expect(kept.isActive)
        #expect(kept.startedAt == (try CoreDataTestHelpers.day("2026-02-01")))
        #expect(kept.track === olderTrack)
        #expect(note.studentTrackEnrollmentID == low.uuidString)
    }
}
