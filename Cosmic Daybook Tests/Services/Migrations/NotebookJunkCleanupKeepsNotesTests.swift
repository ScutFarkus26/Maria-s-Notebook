import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Clean Up Leftovers fixes from the 2026-10-05 data-model hunt: a completed-work
// entry of deleted work takes its notes with it only by cascade, so they're
// detached first (#4); and two completions of one reminder on different
// moments are two reminders, not copies (#48).

@Suite("Notebook junk cleanup keeps notes and distinct completions")
@MainActor
struct NotebookJunkCleanupKeepsNotesTests {

    private let today: Date

    init() throws {
        today = try CoreDataTestHelpers.day("2026-10-01")
    }

    private func clean(_ context: NSManagedObjectContext) -> NotebookJunkCleanup.Counts {
        let preview = NotebookJunkCleanup.run(in: context, today: today, apply: false)
        #expect(!context.hasChanges, "the preview changed something")
        let done = NotebookJunkCleanup.run(in: context, today: today, apply: true)
        #expect(done == preview)
        #expect(CoreDataTestHelpers.save(context))
        return done
    }

    @Test("A completed-work entry of deleted work goes; the notes written on it stay, and the preview counts them")
    func completionNotesKept() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        let gone = CDWorkCompletionRecord(context: context)
        gone.workID = UUID().uuidString
        gone.studentID = child.uuidString
        let note = CoreDataTestHelpers.seedNote(in: context, body: "Finished the long division booklet")
        note.scope = .student(child)
        note.workCompletionRecord = gone
        let second = CoreDataTestHelpers.seedNote(in: context, body: "Checked it with a friend")
        second.workCompletionRecord = gone
        CoreDataTestHelpers.save(context)
        let noteID = note.objectID

        let done = clean(context)
        #expect(done.completionRecordsOfDeletedWork == 1)
        #expect(done.completionNotesKept == 2)
        #expect(done.lines.contains("2 notes written on those entries kept in the children's notes"))
        #expect(context.safeFetch(CDFetchRequest(CDWorkCompletionRecord.self)).isEmpty)

        let notes = context.safeFetch(CDFetchRequest(CDNote.self))
        #expect(notes.count == 2)
        #expect(notes.allSatisfy { $0.workCompletionRecord == nil })
        let kept = try #require(context.existingObject(with: noteID) as? CDNote)
        #expect(kept.searchIndexStudentID == child)
    }

    @Test("A note that arrives after the preview is detached too, not cascaded away")
    func noteArrivingAfterPreviewKept() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let gone = CDWorkCompletionRecord(context: context)
        gone.workID = UUID().uuidString
        CoreDataTestHelpers.save(context)

        let preview = NotebookJunkCleanup.run(in: context, today: today, apply: false)
        #expect(preview.completionRecordsOfDeletedWork == 1)
        #expect(preview.completionNotesKept == 0)
        let late = CoreDataTestHelpers.seedNote(in: context, body: "Synced in from the iPad")
        late.workCompletionRecord = gone
        CoreDataTestHelpers.save(context)

        _ = NotebookJunkCleanup.run(in: context, today: today, apply: true, within: preview)
        #expect(CoreDataTestHelpers.save(context))
        #expect(context.safeFetch(CDFetchRequest(CDWorkCompletionRecord.self)).isEmpty)
        #expect(context.safeFetch(CDFetchRequest(CDNote.self)).map(\.body) == ["Synced in from the iPad"])
    }

    @Test("One reminder completed at two different moments is two reminders; one moment twice is a copy")
    func completedRemindersGroupByMoment() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let due = try CoreDataTestHelpers.day("2026-09-11")
        let monday = try CoreDataTestHelpers.day("2026-09-14").addingTimeInterval(9 * 3_600)
        let friday = try CoreDataTestHelpers.day("2026-09-18").addingTimeInterval(14 * 3_600)
        func done(_ title: String, at completedAt: Date, created: String) throws {
            let row = CDReminder(context: context)
            row.title = title
            row.dueDate = due
            row.isCompleted = true
            row.completedAt = completedAt
            row.createdAt = try CoreDataTestHelpers.day(created)
        }
        try done("Order paper", at: monday, created: "2025-04-26")
        try done("Order paper", at: friday, created: "2025-05-01")
        try done("Call the office", at: monday, created: "2025-04-26")
        try done("Call the office", at: monday, created: "2025-05-01")
        CoreDataTestHelpers.save(context)

        let cleaned = clean(context)
        #expect(cleaned.duplicateReminders == 1)
        let left = context.safeFetch(CDFetchRequest(CDReminder.self))
        #expect(left.filter { $0.title == "Order paper" }.count == 2)
        #expect(left.filter { $0.title == "Call the office" }.map(\.createdAt)
            == [try CoreDataTestHelpers.day("2025-04-26")])
    }
}
