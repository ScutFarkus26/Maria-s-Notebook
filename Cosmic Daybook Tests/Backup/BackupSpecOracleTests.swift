import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Holds the backup's table-driven code (`ModelRow`) to the hand-written code
/// it replaces, type by type, for the 38 types "Simplify round two", Phase 7
/// moves onto it. The old code is frozen in this target as it stood at
/// a906650c0 (`LegacyBackupDTOs.swift`, `LegacyBackupDTOTransformers.swift`,
/// `LegacyBackupEntityImporter.swift`), less the track parts main took out of
/// that same code at schema 23 (94b12ace9: `SequenceTrack` and the `trackID`,
/// `trackStepID` and `studentTrackEnrollmentID` fields; Phase 8 applied the
/// same removal to the copy), and `oracleTypes` (`+Table`) says how it
/// exported and restored each type, 37 since then. Three things are compared:
///
/// - Export: each type's rows as the app writes them and as the old code wrote
///   them, as JSON objects, for the field-coverage fixture (every attribute
///   set) and for a sparse one (every optional attribute nil, and a record
///   with no `id`). A value the old code made up (a `Date()`, a `UUID()`), one
///   that differs between two of its own exports, is compared only for being
///   written at all.
/// - Reading: each type's row in the golden backup, whole and less each one of
///   its keys in turn, is read by both the old row type and the app's reader,
///   or refused by both.
/// - Restoring: a row both read, merged into a store holding the fixture,
///   leaves the type's records the same through the old importer as through
///   the app's restore: every attribute, and every to-one relationship's
///   target. Once into a store holding the row's record (an update), once into
///   one without it (an insert).
///
/// It passes trivially while a type is still hand-written, the app running the
/// same code; it is the check that moving a type to `ModelRow` changed nothing.
@Suite("Backup spec oracle", .serialized)
@MainActor
struct BackupSpecOracleTests {
    @Test("The table holds every hand-written type once, in archive order, under its archive name")
    func tableCoversTheTypes() {
        #expect(Self.oracleTypes.map(\.entityName) == Self.entityNames)
        #expect(Self.entityNames.count == 37)
        #expect(BackupEntityTable.names.filter(Set(Self.entityNames).contains) == Self.entityNames)
        for oracle in Self.oracleTypes {
            let entity = BackupEntityTable.entities.first { $0.name == oracle.entityName }
            #expect(entity?.managedType() == oracle.managedType, "\(oracle.entityName) is another class in the table")
        }
    }

    // MARK: - Export

    @Test("Every type writes the fixture as the hand-written code did")
    func exportMatchesOnFullFixture() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        try BackupFieldCoverageTests.seedEveryBackedUpEntity(into: stack.viewContext)
        #expect(CoreDataTestHelpers.save(stack.viewContext), "Fixture save failed")
        try await Self.expectSameExport(of: stack.viewContext, situation: "full fixture", everyTypeWrites: true)
    }

    @Test("Every type writes sparse records, and one with no id, as the hand-written code did")
    func exportMatchesOnSparseFixture() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext
        for (index, oracle) in Self.oracleTypes.enumerated() {
            let name = try #require(Self.entityName(of: oracle.managedType, in: context))
            NSEntityDescription.insertNewObject(forEntityName: name, into: context)
                .setValue(Self.fixedUUID(index), forKey: "id")
            _ = NSEntityDescription.insertNewObject(forEntityName: name, into: context)
        }
        #expect(CoreDataTestHelpers.save(context), "Sparse fixture save failed")
        try await Self.expectSameExport(of: context, situation: "sparse fixture", everyTypeWrites: false)
    }

    /// Each type's rows from `context`, through the old code twice (a moment
    /// apart, so a made-up date differs) and through the app between them.
    private static func expectSameExport(
        of context: NSManagedObjectContext,
        situation: String,
        everyTypeWrites: Bool
    ) async throws {
        let first = try oracleTypes.map { try $0.legacyExport(context) }
        try await Task.sleep(for: .milliseconds(20))
        let entries = try BackupWriter.serializeEntries(from: BackupService().collectPayload(viewContext: context))
        try await Task.sleep(for: .milliseconds(20))
        let second = try oracleTypes.map { try $0.legacyExport(context) }

        for (index, oracle) in oracleTypes.enumerated() {
            let name = oracle.entityName
            let written = entries.first { $0.entityName == name }.map(BackupReader.ndjsonLines(in:)) ?? []
            if everyTypeWrites {
                #expect(!first[index].isEmpty, "\(situation): the old code wrote no \(name) rows")
            }
            expectSameRows(
                old: first[index].compactMap(object), oldAgain: second[index].compactMap(object),
                new: written.compactMap(object), situation: "\(situation), \(name)"
            )
        }
    }

    /// Rows matched by `id` where the old code's two exports agree on it; the
    /// rest (an id it made up) in the order written.
    private static func expectSameRows(
        old: [[String: Any]],
        oldAgain: [[String: Any]],
        new: [[String: Any]],
        situation: String
    ) {
        #expect(new.count == old.count, "\(situation): \(old.count) rows from the old code, \(new.count) now")
        guard oldAgain.count == old.count else {
            Issue.record("\(situation): the old code wrote \(old.count) rows, then \(oldAgain.count)")
            return
        }
        let id = { (row: [String: Any]) in row["id"] as? String }
        let kept = Set(old.compactMap(id)).intersection(oldAgain.compactMap(id))
        let byID = { (rows: [[String: Any]]) -> [String: [String: Any]] in
            var result: [String: [String: Any]] = [:]
            for row in rows {
                if let key = id(row), kept.contains(key), result[key] == nil { result[key] = row }
            }
            return result
        }
        let loose = { (rows: [[String: Any]]) in rows.filter { id($0).map(kept.contains) != true } }
        let (oldByID, againByID, newByID) = (byID(old), byID(oldAgain), byID(new))
        for key in kept.sorted() {
            guard let was = oldByID[key], let again = againByID[key] else { continue }
            guard let now = newByID[key] else {
                Issue.record("\(situation): row \(key) is written by the old code only")
                continue
            }
            expectSameRow(was, again, now, situation: "\(situation) row \(key)")
        }
        for key in Set(newByID.keys).subtracting(kept).sorted() {
            Issue.record("\(situation): row \(key) is written now only")
        }
        let (oldLoose, againLoose, newLoose) = (loose(old), loose(oldAgain), loose(new))
        #expect(
            newLoose.count == oldLoose.count,
            "\(situation): \(oldLoose.count) rows with a made-up id from the old code, \(newLoose.count) now"
        )
        for (offset, (was, now)) in zip(oldLoose, newLoose).enumerated() where offset < againLoose.count {
            expectSameRow(was, againLoose[offset], now, situation: "\(situation) row with a made-up id")
        }
    }

    private static func expectSameRow(
        _ old: [String: Any],
        _ oldAgain: [String: Any],
        _ new: [String: Any],
        situation: String
    ) {
        for key in Set(old.keys).union(oldAgain.keys).union(new.keys).sorted() {
            let (was, again, now) = (canonical(old[key]), canonical(oldAgain[key]), canonical(new[key]))
            if was != again {
                // Made up as it was written: only whether it is written counts.
                #expect(
                    (old[key] == nil) == (new[key] == nil),
                    "\(situation): \(key) (made up) was \(was), now \(now)"
                )
            } else if was != now {
                Issue.record("\(situation): \(key) was \(was), now \(now)")
            }
        }
    }

    // MARK: - Reading and restoring

    @Test(
        "A type's golden row, whole and less each key, reads and restores as the hand-written code did",
        arguments: entityNames
    )
    func restoreMatches(entityName: String) async throws {
        let oracle = try #require(Self.oracleTypes.first { $0.entityName == entityName })
        let golden = try #require(Self.golden.keys.first { $0.hasSuffix("/\(entityName)") })
        let storeName = String(golden.prefix { $0 != "/" })
        let body = Data((Self.golden[golden] ?? "").utf8)
        let lines = BackupReader.ndjsonLines(
            in: BackupEntityEntry(entityName: entityName, storeName: storeName, count: 0, ndjson: body)
        )
        #expect(!lines.isEmpty, "The golden backup holds no \(entityName) row")
        for line in lines {
            let row = try #require(try JSONSerialization.jsonObject(with: line) as? [String: Any])
            let recordID = try #require((row["id"] as? String).flatMap(UUID.init(uuidString:)))
            var cases: [Case] = [Case(removed: nil, line: line)]
            for key in row.keys.sorted() {
                var less = row
                less[key] = nil
                let lessLine = try JSONSerialization.data(withJSONObject: less, options: [.sortedKeys])
                cases.append(Case(removed: key, line: lessLine))
            }
            // Read by both, or refused by both; only what both read is restored.
            let readings = cases.compactMap { expectSameReading($0, oracle: oracle, storeName: storeName) }
            for target in Target.allCases {
                let stores = try FixturePair(of: oracle.managedType, without: target == .insert ? recordID : nil)
                for reading in readings {
                    try await expectSameRestore(reading, oracle: oracle, target: target, recordID: recordID, in: stores)
                    try stores.putBack()
                }
            }
        }
    }

    private struct Case {
        let removed: String?
        let line: Data

        var situation: String { "row " + (removed.map { "without \"\($0)\"" } ?? "whole") }
    }

    /// A line both read: the old restore of it, and the app's payload.
    private struct Reading {
        let situation: String
        let isWhole: Bool
        let oldRestore: LegacyRestore
        let payload: BackupPayload
    }

    private enum Target: String, CaseIterable {
        case update = "into a store holding its record"
        case insert = "into a store without its record"
    }

    private func expectSameReading(_ test: Case, oracle: OracleType, storeName: String) -> Reading? {
        let situation = "\(oracle.entityName) \(test.situation)"
        let oldRestore = oracle.legacyImport(test.line)
        let payload = Self.appRead(test.line, entityName: oracle.entityName, storeName: storeName)
        guard (oldRestore == nil) == (payload == nil) else {
            Issue.record("""
                \(situation): the old row type \(oldRestore == nil ? "refuses" : "reads") it, \
                the app \(payload == nil ? "refuses" : "reads") it
                """)
            return nil
        }
        if test.removed == nil {
            #expect(oldRestore != nil, "\(situation): neither the old row type nor the app reads it")
        }
        guard let oldRestore, let payload else { return nil }
        return Reading(situation: situation, isWhole: test.removed == nil, oldRestore: oldRestore, payload: payload)
    }

    private func expectSameRestore(
        _ reading: Reading,
        oracle: OracleType,
        target: Target,
        recordID: UUID,
        in stores: FixturePair
    ) async throws {
        let label = "\(reading.situation), merged \(target.rawValue)"
        let oldFailure = Result { try reading.oldRestore(stores.old) }.failure
        let newFailure = await Self.appMerge(reading.payload, into: stores.new)
        guard (oldFailure == nil) == (newFailure == nil) else {
            Issue.record("\(label): the old restore \(oldFailure ?? "succeeds"), the app's \(newFailure ?? "succeeds")")
            return
        }
        guard oldFailure == nil else { return }
        let old = try Self.records(of: oracle.managedType, in: stores.old)
        let new = try Self.records(of: oracle.managedType, in: stores.new)
        if reading.isWhole, target == .insert, oracle.entityName != "CalendarEvent" {
            // Not vacuous: the whole row makes a record (CalendarEvent is carried, never restored).
            #expect(old[recordID.uuidString] != nil, "\(label): the old restore made no record")
        }
        Self.expectSameRecords(old: old, new: new, situation: label)
    }

    private static func expectSameRecords(
        old: [String: [String: String]],
        new: [String: [String: String]],
        situation: String
    ) {
        for id in Set(old.keys).union(new.keys).sorted() {
            guard let was = old[id], let now = new[id] else {
                let only = old[id] == nil ? "app's" : "old code's"
                Issue.record("\(situation): record \(id) is in the \(only) store only")
                continue
            }
            for field in Set(was.keys).union(now.keys).sorted() where was[field] != now[field] {
                Issue.record("""
                    \(situation): \(field) is \(was[field] ?? "missing") through the old code, \
                    \(now[field] ?? "missing") through the app
                    """)
            }
        }
    }
}

private extension Result where Failure == any Error {
    /// The error's text, or nil on success.
    var failure: String? {
        if case .failure(let error) = self { "\(error)" } else { nil }
    }
}
