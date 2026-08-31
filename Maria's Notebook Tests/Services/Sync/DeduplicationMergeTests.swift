import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

/// Correctness tests for the deduplication merge logic in
/// `DataCleanupService+Deduplication`. Dedup runs automatically after backup
/// imports and CloudKit re-imports, and it deletes records — a merge bug here
/// silently destroys classroom data, so these tests pin down the guarantees:
/// counts shrink by exactly the duplicate count, flags and text survive on the
/// merged record, and Cascade-owned children are re-parented instead of deleted.
@Suite("Deduplication Merge Logic")
@MainActor
final class DeduplicationMergeTests {

    private struct FollowUpBundle: Equatable {
        let actionRaw: String?
        let reviewAt: Date?
        let resolvedAt: Date?
        let resolutionRaw: String?
        let updatedAt: Date?
        let evidenceRaw: String?
        let note: String?
        let supportRaw: String?
    }

    /// Deterministic UUIDs whose string order matches the numeric suffix,
    /// so tests can rely on the "lowest id survives" rule.
    private func uuid(_ suffix: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", suffix))!
    }

    private func followUpBundle(_ row: CDLessonPresentation) -> FollowUpBundle {
        FollowUpBundle(
            actionRaw: row.followUpActionRaw,
            reviewAt: row.followUpReviewAt,
            resolvedAt: row.followUpResolvedAt,
            resolutionRaw: row.followUpResolutionRaw,
            updatedAt: row.followUpUpdatedAt,
            evidenceRaw: row.followUpEvidenceRaw,
            note: row.followUpNote,
            supportRaw: row.followUpSupportRaw
        )
    }

    // MARK: - Generic id-based dedup

    @Test("Same-id notes collapse to one record without losing body or flags")
    func noteDedupMergesFields() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext

        let sharedID = uuid(1)
        let blank = CDNote(context: ctx)
        blank.id = sharedID
        blank.body = ""
        blank.isPinned = false
        blank.includeInReport = true

        let filled = CDNote(context: ctx)
        filled.id = sharedID
        filled.body = "Observed careful bead work"
        filled.isPinned = true
        filled.includeInReport = false

        #expect(CoreDataTestHelpers.save(ctx))

        let removed = DataCleanupService.deduplicateNotesStrong(using: ctx)
        #expect(removed == 1)

        let remaining = ctx.safeFetch(CDFetchRequest(CDNote.self))
        #expect(remaining.count == 1)
        let survivor = try #require(remaining.first)
        // The survivor is whichever record the fetch returned first, so assert
        // outcomes that must hold either way: non-empty text and set flags win.
        #expect(survivor.body == "Observed careful bead work")
        #expect(survivor.isPinned)
        #expect(survivor.includeInReport)
    }

    @Test("Notes with distinct ids are never merged")
    func distinctIDsUntouched() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext

        let first = CDNote(context: ctx)
        first.id = uuid(1)
        first.body = "First"
        let second = CDNote(context: ctx)
        second.id = uuid(2)
        second.body = "Second"
        #expect(CoreDataTestHelpers.save(ctx))

        let removed = DataCleanupService.deduplicateNotesStrong(using: ctx)
        #expect(removed == 0)
        #expect(ctx.safeFetch(CDFetchRequest(CDNote.self)).count == 2)
    }

    // MARK: - Attendance semantic dedup (same student + same day)

    @Test("Attendance duplicates for one student-day keep the marked record and its real mark")
    func attendanceDedupPreservesMark() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let studentID = UUID().uuidString
        let day = AppCalendar.startOfDay(Date())

        let unmarked = CDAttendanceRecord(context: ctx)
        unmarked.id = uuid(1)
        unmarked.studentID = studentID
        unmarked.date = day
        unmarked.status = .unmarked

        let marked = CDAttendanceRecord(context: ctx)
        marked.id = uuid(2)
        marked.studentID = studentID
        marked.date = day.addingTimeInterval(3600) // same calendar day, later time
        marked.status = .absent

        // Attach a note to the record that will be deleted (the unmarked loser).
        // Nothing cascades now that the link is a string FK, so the note would
        // dangle on a deleted id unless dedup re-points it at the survivor.
        let note = CDNote(context: ctx)
        note.body = "Parent called ahead"
        note.attendanceRecordID = uuid(1).uuidString

        #expect(CoreDataTestHelpers.save(ctx))

        let removed = DataCleanupService.deduplicateAttendanceRecordsStrong(using: ctx)
        #expect(removed == 1)

        let records = ctx.safeFetch(CDFetchRequest(CDAttendanceRecord.self))
        #expect(records.count == 1)
        let survivor = try #require(records.first)
        // The marked record wins outright — same winner the grid was showing.
        #expect(survivor.id == uuid(2))
        #expect(survivor.status == .absent)

        let notes = ctx.safeFetch(CDFetchRequest(CDNote.self))
        #expect(notes.count == 1)
        #expect(notes.first?.attendanceRecordID == uuid(2).uuidString)
    }

    @Test("A survivor that already has a mark keeps it over the duplicate's mark")
    func attendanceDedupKeepsExistingMark() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let studentID = UUID().uuidString
        let day = AppCalendar.startOfDay(Date())

        let present = CDAttendanceRecord(context: ctx)
        present.id = uuid(1)
        present.studentID = studentID
        present.date = day
        present.status = .present

        let absent = CDAttendanceRecord(context: ctx)
        absent.id = uuid(2)
        absent.studentID = studentID
        absent.date = day
        absent.status = .absent

        #expect(CoreDataTestHelpers.save(ctx))
        #expect(DataCleanupService.deduplicateAttendanceRecordsStrong(using: ctx) == 1)

        let survivor = try #require(ctx.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).first)
        #expect(survivor.id == uuid(1))
        #expect(survivor.status == .present)
    }

    @Test("Attendance records on different days are left alone")
    func attendanceDifferentDaysUntouched() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let studentID = UUID().uuidString
        let today = AppCalendar.startOfDay(Date())

        let first = CDAttendanceRecord(context: ctx)
        first.studentID = studentID
        first.date = today
        let second = CDAttendanceRecord(context: ctx)
        second.studentID = studentID
        second.date = AppCalendar.addingDays(1, to: today)
        #expect(CoreDataTestHelpers.save(ctx))

        #expect(DataCleanupService.deduplicateAttendanceRecordsStrong(using: ctx) == 0)
        #expect(ctx.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).count == 2)
    }

    // MARK: - Draft lesson assignment dedup

    @Test("Draft assignment duplicates merge onto the earliest copy, keeping flags, text, and notes")
    func draftAssignmentDedupMerges() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let lessonID = UUID().uuidString
        let studentA = UUID().uuidString
        let studentB = UUID().uuidString

        let older = CDLessonAssignment(context: ctx)
        older.createdAt = Date(timeIntervalSince1970: 1_000)
        older.lessonID = lessonID
        older.studentIDs = [studentA, studentB]

        let newer = CDLessonAssignment(context: ctx)
        newer.createdAt = Date(timeIntervalSince1970: 2_000)
        newer.lessonID = lessonID
        newer.studentIDs = [studentB, studentA] // same set, different order
        newer.needsPractice = true
        newer.needsAnotherPresentation = true
        newer.notes = "Repeat with golden beads"
        newer.followUpWork = "Stamp game"

        // Observation note attached to the duplicate — unifiedNotes is Cascade,
        // so dedup must move it to the survivor before deleting.
        let observation = CDNote(context: ctx)
        observation.body = "Struggled with exchanging"
        observation.lessonAssignment = newer

        #expect(CoreDataTestHelpers.save(ctx))

        DataCleanupService.deduplicateDraftLessonAssignments(using: ctx)

        let drafts = ctx.safeFetch(CDFetchRequest(CDLessonAssignment.self))
        #expect(drafts.count == 1)
        let survivor = try #require(drafts.first)
        #expect(survivor.id == older.id)
        #expect(survivor.needsPractice)
        #expect(survivor.needsAnotherPresentation)
        #expect(survivor.notes == "Repeat with golden beads")
        #expect(survivor.followUpWork == "Stamp game")

        let notes = ctx.safeFetch(CDFetchRequest(CDNote.self))
        #expect(notes.count == 1)
        #expect(notes.first?.lessonAssignment == survivor)
    }

    @Test("Drafts for different student groups are not merged")
    func draftAssignmentDifferentGroupsUntouched() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let lessonID = UUID().uuidString

        let groupOne = CDLessonAssignment(context: ctx)
        groupOne.lessonID = lessonID
        groupOne.studentIDs = [UUID().uuidString]

        let groupTwo = CDLessonAssignment(context: ctx)
        groupTwo.lessonID = lessonID
        groupTwo.studentIDs = [UUID().uuidString]

        #expect(CoreDataTestHelpers.save(ctx))
        DataCleanupService.deduplicateDraftLessonAssignments(using: ctx)
        #expect(ctx.safeFetch(CDFetchRequest(CDLessonAssignment.self)).count == 2)
    }

    // MARK: - Presentation follow-up dedup

    @Test("Lesson presentation dedup keeps the entire newest follow-up decision together")
    func lessonPresentationDedupKeepsNewestFollowUpBundle() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext
        let sharedID = uuid(9)
        let olderUpdate = Date(timeIntervalSince1970: 2_000)
        let newerUpdate = Date(timeIntervalSince1970: 3_000)
        let reviewAt = Date(timeIntervalSince1970: 4_000)
        let resolvedAt = Date(timeIntervalSince1970: 5_000)

        let canonical = CDLessonPresentation(context: ctx)
        canonical.id = sharedID
        canonical.createdAt = Date(timeIntervalSince1970: 1_000)
        canonical.followUpAction = .watchWork
        canonical.followUpUpdatedAt = olderUpdate
        canonical.followUpEvidence = [.choseIndependently]
        canonical.followUpNote = "Older observation"

        let duplicate = CDLessonPresentation(context: ctx)
        duplicate.id = sharedID
        duplicate.createdAt = Date(timeIntervalSince1970: 1_500)
        duplicate.followUpAction = .planSupport
        duplicate.followUpReviewAt = reviewAt
        duplicate.followUpResolvedAt = resolvedAt
        duplicate.followUpResolution = .supportOrRepresent
        duplicate.followUpUpdatedAt = newerUpdate
        duplicate.followUpEvidence = [.concentrated, .encounteredDifficulty]
        duplicate.followUpNote = "Newer factual observation"
        duplicate.followUpSupport = .confer
        let expectedBundle = followUpBundle(duplicate)

        #expect(CoreDataTestHelpers.save(ctx))
        #expect(DataCleanupService.deduplicateLessonPresentationsStrong(using: ctx) == 1)

        let remaining = ctx.safeFetch(CDFetchRequest(CDLessonPresentation.self))
        let survivor = try #require(remaining.first)
        #expect(remaining.count == 1)
        #expect(survivor.objectID == canonical.objectID)
        #expect(followUpBundle(survivor) == expectedBundle)
    }

    // MARK: - Work model dedup re-parents Cascade children

    @Test("Work model dedup keeps check-ins from both duplicate copies")
    func workDedupKeepsCheckIns() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext

        let sharedID = uuid(7)
        let workA = CDWorkModel(context: ctx)
        workA.id = sharedID
        workA.title = "Checkerboard"
        let workB = CDWorkModel(context: ctx)
        workB.id = sharedID
        workB.title = "Checkerboard"

        let checkA = CDWorkCheckIn(context: ctx)
        checkA.work = workA
        checkA.workID = sharedID.uuidString
        let checkB = CDWorkCheckIn(context: ctx)
        checkB.work = workB
        checkB.workID = sharedID.uuidString

        #expect(CoreDataTestHelpers.save(ctx))

        let removed = DataCleanupService.deduplicateWorkModelsStrong(using: ctx)
        #expect(removed == 1)

        let works = ctx.safeFetch(CDFetchRequest(CDWorkModel.self))
        #expect(works.count == 1)
        let survivor = try #require(works.first)

        let checkIns = ctx.safeFetch(CDFetchRequest(CDWorkCheckIn.self))
        #expect(checkIns.count == 2)
        #expect(checkIns.allSatisfy { $0.work == survivor })
    }

    // MARK: - Full pass

    @Test("deduplicateAllModels reports only entity types that actually shrank")
    func allModelsReportsCounts() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = stack.viewContext

        let sharedID = uuid(3)
        let first = CDNote(context: ctx)
        first.id = sharedID
        first.body = "Dup"
        let second = CDNote(context: ctx)
        second.id = sharedID
        second.body = "Dup"
        CoreDataTestHelpers.seedStudent(in: ctx) // unique — must not be touched
        #expect(CoreDataTestHelpers.save(ctx))

        let results = DataCleanupService.deduplicateAllModels(using: ctx)
        #expect(results["Note"] == 1)
        #expect(results["Student"] == nil)
        #expect(ctx.safeFetch(CDFetchRequest(CDStudent.self)).count == 1)
    }
}
