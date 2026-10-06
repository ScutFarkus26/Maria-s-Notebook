import CoreData
import CryptoKit
import Foundation
import Testing
@testable import CosmicDaybook

// Comparing two restored stores: every record of every entity, and what a
// backup of each would hold.
extension BackupRestoreFixtures {

    /// Every record of every entity in `context`, as comparable lines: each
    /// attribute by name, each to-one relationship as its target's `id`, each
    /// to-many as its targets' ids, sorted. Dates from the last hour — stamped
    /// by an insert or a restore rather than carried by a backup — read
    /// "recent"; binary data reads as its length and digest. Lines are sorted,
    /// so fetch order doesn't matter.
    static func snapshot(of context: NSManagedObjectContext) throws -> [String: [String]] {
        guard let model = context.persistentStoreCoordinator?.managedObjectModel else { return [:] }
        let recent = Date().addingTimeInterval(-3_600)
        var result: [String: [String]] = [:]
        for entity in model.entities where !entity.isAbstract {
            guard let name = entity.name else { continue }
            let request = NSFetchRequest<NSManagedObject>(entityName: name)
            request.includesSubentities = false
            let objects = try context.fetch(request)
            guard !objects.isEmpty else { continue }
            result[name] = objects.map { line(for: $0, entity: entity, recent: recent) }.sorted()
        }
        return result
    }

    private static func line(for object: NSManagedObject, entity: NSEntityDescription, recent: Date) -> String {
        var parts: [String] = []
        for key in entity.attributesByName.keys.sorted() {
            parts.append("\(key)=\(text(object.value(forKey: key), recent: recent))")
        }
        for (key, relationship) in entity.relationshipsByName.sorted(by: { $0.key < $1.key }) {
            let value = object.value(forKey: key)
            if relationship.isToMany {
                let targets = (value as? NSSet)?.allObjects ?? (value as? NSOrderedSet)?.array ?? []
                let ids = targets.compactMap { ($0 as? NSManagedObject).map(identity) }.sorted()
                parts.append("\(key)=[\(ids.joined(separator: ","))]")
            } else {
                parts.append("\(key)=\((value as? NSManagedObject).map(identity) ?? "nil")")
            }
        }
        return parts.joined(separator: " | ")
    }

    private static func identity(_ object: NSManagedObject) -> String {
        guard object.entity.attributesByName["id"] != nil,
              let id = object.value(forKey: "id") as? UUID else { return "<\(object.entity.name ?? "?")>" }
        return id.uuidString
    }

    private static func text(_ value: Any?, recent: Date) -> String {
        guard let value, !(value is NSNull) else { return "nil" }
        switch value {
        case let date as Date:
            return date > recent ? "recent" : "\(date.timeIntervalSinceReferenceDate)"
        case let uuid as UUID:
            return uuid.uuidString
        case let data as Data:
            // A JSON blob (a note's scope) by content: it is encoded without
            // sorted keys, so its bytes differ from one encode to the next.
            if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
               let sorted = try? JSONSerialization.data(
                   withJSONObject: json, options: [.sortedKeys, .fragmentsAllowed]
               ) {
                return "json(\(String(bytes: sorted, encoding: .utf8) ?? ""))"
            }
            let digest = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
            return "data(\(data.count),\(digest))"
        default:
            return "\(value)"
        }
    }

    /// `rows` without the types a restore leaves as they are
    /// (`BackupEntityRegistry.keptOnRestoreEntityNames`), which the one-pass
    /// restore still wrote: since 2026-10-05 a restore leaves the device's
    /// EventKit copies (reminders, calendar events) to the next sync.
    private static func restorable<Value>(_ rows: [String: Value]) -> [String: Value] {
        rows.filter { !BackupEntityRegistry.keptOnRestoreEntityNames.contains($0.key) }
    }

    /// Names every entity whose records differ, with the first differing line.
    static func expectSameStore(
        _ new: NSManagedObjectContext,
        _ old: NSManagedObjectContext,
        _ situation: String
    ) throws {
        let now = restorable(try snapshot(of: new))
        let before = restorable(try snapshot(of: old))
        #expect(now.keys.sorted() == before.keys.sorted(), "\(situation): entities with records")
        for name in Set(now.keys).union(before.keys).sorted() {
            let rows = now[name] ?? []
            let oldRows = before[name] ?? []
            guard rows != oldRows else { continue }
            let first = zip(rows, oldRows).first { $0 != $1 }
            Issue.record("""
                \(situation): \(name) differs (\(rows.count) records now, \(oldRows.count) before).
                now:    \(first?.0 ?? rows.first ?? "")
                before: \(first?.1 ?? oldRows.first ?? "")
                """)
        }
    }

    /// Names every type whose backed-up rows differ, with the first differing
    /// row. As in `snapshot`, a date from the last hour — stamped while the
    /// test ran (the two stores are prepared a moment apart), not carried by a
    /// backup — reads "recent".
    static func expectSameBackup(
        _ new: NSManagedObjectContext,
        _ old: NSManagedObjectContext,
        _ situation: String
    ) throws {
        let recent = Date().addingTimeInterval(-3_600)
        let comparable = { (rows: [Data]) in
            rows.map { withRecentDates($0, after: recent) }.sorted { $0.lexicographicallyPrecedes($1) }
        }
        let now = restorable(try backedUpRows(of: new).mapValues(comparable))
        let before = restorable(try backedUpRows(of: old).mapValues(comparable))
        #expect(now.keys.sorted() == before.keys.sorted(), "\(situation): backed-up types")
        for name in Set(now.keys).union(before.keys).sorted() {
            let rows = now[name] ?? []
            let oldRows = before[name] ?? []
            guard rows != oldRows else { continue }
            let first = zip(rows, oldRows).first { $0 != $1 }
            let text = { (row: Data?) in row.flatMap { String(bytes: $0, encoding: .utf8) } ?? "" }
            Issue.record("""
                \(situation): a backup's \(name) rows differ (\(rows.count) now, \(oldRows.count) before).
                now:    \(text(first?.0 ?? rows.first))
                before: \(text(first?.1 ?? oldRows.first))
                """)
        }
    }

    /// `row` with its dates after `recent` read "recent", its keys sorted.
    private static func withRecentDates(_ row: Data, after recent: Date) -> Data {
        guard var object = try? JSONSerialization.jsonObject(with: row) as? [String: Any] else { return row }
        for (key, value) in object {
            if let text = value as? String, let date = try? Date(text, strategy: .iso8601), date > recent {
                object[key] = "recent"
            }
        }
        let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
        return (try? JSONSerialization.data(withJSONObject: object, options: options)) ?? row
    }

    /// `context` as a backup writes it: each type's NDJSON lines, sorted (a
    /// Note's scope with its keys in order, see `Fixtures.comparable`).
    static func backedUpRows(of context: NSManagedObjectContext) throws -> [String: [Data]] {
        let payload = BackupPipelineRecorder.$current.withValue(recorder()) {
            BackupService().collectPayload(viewContext: context)
        }
        var rows: [String: [Data]] = [:]
        for entry in try BackupWriter.serializeEntries(from: payload) {
            let comparable = try Fixtures.comparable(entry.ndjson, entityName: entry.entityName)
            rows[entry.entityName] = Fixtures.sortedLines(comparable)
        }
        return rows
    }
}
