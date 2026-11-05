// BackupEntityImporter+ModelRows.swift
// Restores the entity types written through `ModelRow`.

import CoreData
import Foundation
import OSLog

extension BackupEntityImporter {

    /// Looks up a parent record by id.
    typealias ParentLookup = (UUID) throws -> NSManagedObject?

    /// Restores `ModelRow` records the way their hand-written importers did:
    /// a row the spec doesn't take (`restoresRow`) is passed over; the record
    /// with the row's `id` (`existing`), or a new one, gets every attribute
    /// the row's spec lists, nil for an optional key the row lacks (one the
    /// spec keeps when missing is left as it is), and every computed field is
    /// written; then each of the spec's parents is re-linked through
    /// `parents`, keyed by relationship name. A deferred parent is re-linked
    /// later: the links are returned, for `relinkDeferred`.
    @discardableResult
    static func importRows<Kind: ModelRowKind, Entity: NSManagedObject>(
        _ rows: [ModelRow<Kind>],
        as type: Entity.Type,
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<Entity>,
        parents: [String: ParentLookup] = [:]
    ) -> [BackupDeferredLinks] {
        let spec = Kind.spec
        var deferred: [BackupDeferredLinks] = []
        for row in rows {
            if let restores = spec.restoresRow, !restores(row.values) { continue }
            let object = existingEntity(id: row.id, existing: existing) ?? Entity(context: viewContext)
            object.setValue(row.id, forKey: "id")
            write(row, into: object)
            var later: [BackupDeferredLinks.Target] = []
            for link in spec.parents {
                if link.deferred {
                    if let id = parentID(in: row, at: link.key) {
                        later.append(.init(relationship: link.relationship, id: id))
                    }
                    continue
                }
                guard let lookup = parents[link.relationship] else {
                    assertionFailure("\(spec.entityName): no lookup passed for \(link.relationship)")
                    continue
                }
                relink(object, through: link, row: row, lookup: lookup, entityName: spec.entityName)
            }
            if !later.isEmpty { deferred.append(BackupDeferredLinks(ownerID: row.id, targets: later)) }
            viewContext.insert(object)
        }
        return deferred
    }

    /// Every attribute and computed field of `row`, written onto `object`.
    private static func write<Kind: ModelRowKind>(_ row: ModelRow<Kind>, into object: NSManagedObject) {
        for field in Kind.spec.fields {
            let value = row.values[field.key]
            if value == nil, field.keptWhenMissing { continue }
            switch field.source {
            case .attribute(let attribute):
                if field.storedAsString, case .uuid(let id)? = value {
                    object.setValue(id.uuidString, forKey: attribute)
                } else {
                    object.setValue(value?.storedValue, forKey: attribute)
                }
            case .computed(let code):
                code.write(object, value, row.values)
            case .parentID:
                continue
            }
        }
    }

    /// Sets each deferred relationship to the parent found by its id, or nil,
    /// once every type is in: on the record `owner` finds for the row's `id`
    /// (as the note relink always looked its note up). A failed lookup
    /// stops the restore, as it did there.
    static func relinkDeferred(
        _ links: [BackupDeferredLinks],
        owner: (UUID) throws -> NSManagedObject?,
        parents: [String: ParentLookup]
    ) throws {
        for link in links {
            guard let object = try owner(link.ownerID) else { continue }
            for target in link.targets {
                guard let lookup = parents[target.relationship] else {
                    assertionFailure("No lookup passed for the deferred \(target.relationship)")
                    continue
                }
                object.setValue(try lookup(target.id), forKey: target.relationship)
            }
        }
    }

    /// The parent id a row holds under `key`: a UUID, or a string that is one.
    private static func parentID<Kind: ModelRowKind>(in row: ModelRow<Kind>, at key: String) -> UUID? {
        switch row.values[key] {
        case .uuid(let id): id
        case .string(let text): UUID(uuidString: text)
        default: nil
        }
    }

    private static func relink<Kind: ModelRowKind>(
        _ object: NSManagedObject,
        through link: ParentLink,
        row: ModelRow<Kind>,
        lookup: ParentLookup,
        entityName: String
    ) {
        let parentID = parentID(in: row, at: link.key)
        switch link.missing {
        case .keep:
            guard let parentID else { return }
            do {
                if let parent = try lookup(parentID) {
                    object.setValue(parent, forKey: link.relationship)
                }
            } catch {
                let desc = error.localizedDescription
                let what = "\(entityName).\(link.relationship)"
                Logger.backup.warning("Failed to check \(what, privacy: .public): \(desc, privacy: .public)")
            }
        case .clearWhenNotFound:
            guard let parentID else { return }
            object.setValue(try? lookup(parentID), forKey: link.relationship)
        case .alwaysSet:
            object.setValue(try? lookup(parentID ?? UUID()), forKey: link.relationship)
        }
    }
}

/// One restored record's parents to re-link once every type is in
/// (`ParentLink.deferred`): its `id`, and each relationship's parent id.
nonisolated struct BackupDeferredLinks: Sendable {
    struct Target: Sendable {
        let relationship: String
        let id: UUID
    }

    let ownerID: UUID
    let targets: [Target]
}
