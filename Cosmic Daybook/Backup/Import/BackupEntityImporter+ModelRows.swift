// BackupEntityImporter+ModelRows.swift
// Restores the entity types written through `ModelRow`.

import CoreData
import Foundation
import OSLog

extension BackupEntityImporter {

    /// Looks up a parent record by id.
    typealias ParentLookup = (UUID) throws -> NSManagedObject?

    /// Restores `ModelRow` records the way their hand-written importers did:
    /// the record with the row's `id` (`existing`), or a new one, gets every
    /// attribute the row's spec lists, nil for an optional key the row lacks;
    /// then each of the spec's parents is re-linked through `parents`, keyed by
    /// relationship name.
    static func importRows<Kind: ModelRowKind, Entity: NSManagedObject>(
        _ rows: [ModelRow<Kind>],
        as type: Entity.Type,
        into viewContext: NSManagedObjectContext,
        existing: ExistingLookup<Entity>,
        parents: [String: ParentLookup] = [:]
    ) {
        let spec = Kind.spec
        for row in rows {
            let object = existingEntity(id: row.id, existing: existing) ?? Entity(context: viewContext)
            object.setValue(row.id, forKey: "id")
            for field in spec.fields {
                guard case .attribute = field.source else { continue }
                object.setValue(row.values[field.key]?.storedValue, forKey: field.key)
            }
            for link in spec.parents {
                guard let lookup = parents[link.relationship] else {
                    assertionFailure("\(spec.entityName): no lookup passed for \(link.relationship)")
                    continue
                }
                relink(object, through: link, row: row, lookup: lookup, entityName: spec.entityName)
            }
            viewContext.insert(object)
        }
    }

    private static func relink<Kind: ModelRowKind>(
        _ object: NSManagedObject,
        through link: ParentLink,
        row: ModelRow<Kind>,
        lookup: ParentLookup,
        entityName: String
    ) {
        let parentID: UUID? = switch row.values[link.key] {
        case .uuid(let id): id
        case .string(let text): UUID(uuidString: text)
        default: nil
        }
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
