import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The export collects each entity type a page (1,000 rows) at a time. Until
// 2026-09-26 the pages were read together with the view context's unsaved
// edits, and the loop stopped at the first page that produced fewer than
// 1,000 DTOs. So in a type past one page an unsaved new row was written twice
// and pushed a saved row off the first page, which no page then read, and an
// unsaved delete on the first page had another row written twice; and one row
// a transformer skips (a malformed record) on a full page ended the type
// there, leaving every later page out of the backup. Pinned here on a store
// with notes and attendance past one page: every saved row once, unsaved
// inserts once, unsaved deletes left out, unsaved edits as edited, and a
// skipped row costs only itself.
@Suite("Backup collection pages")
@MainActor
struct BackupCollectionPagingTests {
    private typealias Fixtures = BackupStreamingFixtures

    /// The saved rows' ids, read from the store itself: a dictionary fetch
    /// ignores the context's unsaved changes.
    private static func savedIDs(_ entityName: String, in context: NSManagedObjectContext) throws -> [UUID] {
        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = ["id"]
        return try context.fetch(request).compactMap { $0["id"] as? UUID }
    }

    /// The saved row at `offset` in store order — the order the pages read.
    private static func savedRow(
        _ entityName: String, at offset: Int, in context: NSManagedObjectContext
    ) throws -> NSManagedObject {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.fetchOffset = offset
        request.fetchLimit = 1
        request.includesPendingChanges = false
        return try #require(try context.fetch(request).first)
    }

    /// Saves notes past one 1,000-row page — and nothing else, so each test
    /// holds the main actor briefly (the suite's timing tests share it).
    private static func seedNotes(in context: NSManagedObjectContext) throws {
        for index in 0..<1_205 {
            Fixtures.insertNote("Observation \(index)", into: context)
        }
        try context.save()
    }

    /// Saves attendance records past one 1,000-row page, and nothing else.
    private static func seedAttendance(in context: NSManagedObjectContext) throws {
        let start = Date(timeIntervalSince1970: 1_750_000_000)
        let studentID = UUID().uuidString
        for index in 0..<1_030 {
            let record = NSEntityDescription.insertNewObject(forEntityName: "AttendanceRecord", into: context)
            record.setValue(UUID(), forKey: "id")
            record.setValue(studentID, forKey: "studentID")
            record.setValue(start.addingTimeInterval(Double(index) * 86_400), forKey: "date")
        }
        try context.save()
    }

    @Test("An unsaved note in a type past one page is backed up once, with every saved note")
    func pendingInsertIsCollectedOnce() throws {
        let store = try Fixtures.makeStore()
        defer { store.remove() }
        try Self.seedNotes(in: store.context)
        let saved = try Self.savedIDs("Note", in: store.context)
        #expect(saved.count > 1_000, "the notes fill more than one page")
        let pending = UUID()
        let note = NSEntityDescription.insertNewObject(forEntityName: "Note", into: store.context)
        note.setValue(pending, forKey: "id")
        note.setValue("Typed, not saved", forKey: "body")

        let notes = BackupService().collectPayload(viewContext: store.context).notes.map(\.id)

        #expect(notes.count == saved.count + 1)
        #expect(Set(notes).count == notes.count, "no note is written twice")
        #expect(Set(notes) == Set(saved).union([pending]))
    }

    @Test("An unsaved delete on the first page leaves out that note and no other")
    func pendingDeleteLeavesOutOnlyThatRow() throws {
        let store = try Fixtures.makeStore()
        defer { store.remove() }
        try Self.seedNotes(in: store.context)
        let saved = try Self.savedIDs("Note", in: store.context)
        let first = try Self.savedRow("Note", at: 0, in: store.context)
        let deleted = try #require(first.value(forKey: "id") as? UUID)
        store.context.delete(first)

        let notes = BackupService().collectPayload(viewContext: store.context).notes.map(\.id)

        #expect(notes.count == saved.count - 1)
        #expect(Set(notes) == Set(saved).subtracting([deleted]))
    }

    @Test("An unsaved edit to a saved note past the first page is backed up as edited")
    func pendingUpdateIsCollectedAsEdited() throws {
        let store = try Fixtures.makeStore()
        defer { store.remove() }
        try Self.seedNotes(in: store.context)
        let saved = try Self.savedIDs("Note", in: store.context)
        let later = try Self.savedRow("Note", at: 1_100, in: store.context)
        let edited = try #require(later.value(forKey: "id") as? UUID)
        later.setValue("Edited, not saved", forKey: "body")

        let notes = BackupService().collectPayload(viewContext: store.context).notes

        #expect(notes.count == saved.count)
        #expect(notes.first { $0.id == edited }?.body == "Edited, not saved")
    }

    @Test("A row the transformer skips costs only itself, even on a full page")
    func skippedRowDoesNotEndTheType() async throws {
        let store = try Fixtures.makeStore()
        defer { store.remove() }
        try Self.seedAttendance(in: store.context)
        // The first attendance record in store order, made one the transformer
        // skips: its student id is not a UUID.
        let first = try Self.savedRow("AttendanceRecord", at: 0, in: store.context)
        let skipped = try #require(first.value(forKey: "id") as? UUID)
        first.setValue("not-a-uuid", forKey: "studentID")
        try store.context.save()
        let saved = try Self.savedIDs("AttendanceRecord", in: store.context)
        #expect(saved.count > 1_000, "the records fill more than one page")

        let attendance = BackupService().collectPayload(viewContext: store.context).attendance.map(\.id)
        #expect(attendance.count == saved.count - 1)
        #expect(Set(attendance) == Set(saved).subtracting([skipped]))

        // The streamed export reads through the same collectors.
        let recorder = Fixtures.recorder()
        let summary = try await BackupPipelineRecorder.$current.withValue(recorder) {
            try await BackupWriter.write(viewContext: store.context, to: store.archiveURL("Skipped"))
        }
        #expect(recorder.reached.map(\.phase).contains("write staged"))
        #expect(summary.entityCounts["AttendanceRecord"] == saved.count - 1)
    }
}
