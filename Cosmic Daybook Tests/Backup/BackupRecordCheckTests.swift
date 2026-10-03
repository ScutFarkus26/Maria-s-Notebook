import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// `BackupRecordCheck`: before Remove Last Year or Clean Up Old Records touches a record,
/// the backup made for it must hold that record by `id`, not just as many rows of its type.
@Suite("Backup record check")
@MainActor
struct BackupRecordCheckTests {
    private typealias Fixtures = BackupStreamingFixtures

    private struct Backup {
        let store: Fixtures.Store
        let url: URL
        let marks: [CDAttendanceRecord]
    }

    /// Three attendance records and a backup of them.
    private static func makeBackup() async throws -> Backup {
        let store = try Fixtures.makeStore()
        let marks = (0..<3).map { offset in
            let record = CDAttendanceRecord(context: store.context)
            record.studentID = UUID().uuidString
            record.date = Date(timeIntervalSince1970: 1_750_000_000 + Double(offset) * 86_400)
            return record
        }
        try store.context.save()
        let url = store.archiveURL("Source")
        _ = try await BackupWriter.write(viewContext: store.context, to: url)
        return Backup(store: store, url: url, marks: marks)
    }

    private static func check(_ url: URL, holds records: [NSManagedObjectID], in store: Fixtures.Store) async throws {
        try await BackupRecordCheck.check(url, holds: records, context: store.stack.container.newBackgroundContext())
    }

    @Test("A backup holding every record passes")
    func completeBackupPasses() async throws {
        let backup = try await Self.makeBackup()
        defer { backup.store.remove() }
        try await Self.check(backup.url, holds: backup.marks.map(\.objectID), in: backup.store)
    }

    @Test("A backup with the right count but one record's id swapped for another fails")
    func missingIDFails() async throws {
        let backup = try await Self.makeBackup()
        let (store, marks) = (backup.store, backup.marks)
        defer { store.remove() }
        // The same archive with one mark's id replaced: as many rows, one record missing.
        let source = try Fixtures.contents(of: backup.url)
        let missing = try #require(marks[1].id).uuidString
        let path = "\(BackupWriter.store(for: "AttendanceRecord"))/AttendanceRecord.ndjson"
        let body = try #require(source.bodies[path].flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains(missing))
        let swapped = store.archiveURL("Swapped")
        let key = try BackupEncryptionKeyStore.fetchOrCreateKey()
        try BackupArchive.write(to: swapped, encryptionKey: key) { appender in
            for entry in source.paths {
                let data = entry == path
                    ? Data(body.replacingOccurrences(of: missing, with: UUID().uuidString).utf8)
                    : source.bodies[entry] ?? Data()
                try appender.append(path: entry, data: data)
            }
        }
        #expect(try BackupReader.verifyStructure(at: swapped).entryLineCounts["AttendanceRecord"] == 3)

        do {
            try await Self.check(swapped, holds: marks.map(\.objectID), in: store)
            Issue.record("A backup missing a record passed the check")
        } catch {
            #expect(error.localizedDescription.contains("missing 1 of the AttendanceRecord records"))
        }
        // A run touching only the records the backup holds may go ahead.
        try await Self.check(swapped, holds: [marks[0].objectID, marks[2].objectID], in: store)
    }

    @Test("A record with no id is held to a count: the backup must have a row for every one")
    func recordWithoutIDCounted() {
        let needed = BackupRecordCheck.Needed(withoutID: ["Note": 1])
        let held: [String: Set<UUID>] = ["Note": [UUID(), UUID()]]
        #expect(BackupRecordCheck.problem(needed: needed, held: held, notebookRows: ["Note": 2]) == nil)
        #expect(BackupRecordCheck.problem(needed: needed, held: held, notebookRows: ["Note": 3]) != nil)
    }
}
