//
//  DataCleanupService+DedupKeepers.swift
//  Cosmic Daybook
//
//  Which copy a duplicate cleanup keeps, and how it saves (bug hunt 2026-10-05).
//
//  Every device runs the cleanup on its own, so the copy kept must be chosen
//  from what is the same on every device at every sync state, or two devices
//  can each keep a different copy, delete the other, and both deletes sync.
//  Content isn't (one device may not have seen the latest edit yet), and
//  neither is the CloudKit record name (a copy not yet sent to iCloud has none
//  on the device that made it). Copies of one fact under different ids
//  (attendance, a child's marks after a lesson merge) are kept by the id
//  string; the winning content is then copied onto the kept copy.
//

import CloudKit
import CoreData
import Foundation
import os

nonisolated extension DataCleanupService {

    /// `date` to the whole millisecond, which is all CloudKit keeps: the device
    /// that made a record holds `.1234` where every other device reads `.123`,
    /// and comparing the full value let the two order the same copies apart
    /// (#41). Rounded to the microsecond first, so a value read back from
    /// CloudKit (`.123` held as `.12299999…`) isn't floored a millisecond low.
    static func millisecondKey(_ date: Date?) -> Int64? {
        guard let date else { return nil }
        let micros = (date.timeIntervalSince1970 * 1_000_000).rounded()
        return Int64((micros / 1000).rounded(.down))
    }

    /// Identity order, for copies of one fact under different ids: the lowest
    /// `id` string first (a row without one last), then the CloudKit record
    /// name to break an id tie, then the object URI.
    static func identityPrecedes(
        _ lhs: NSManagedObject, _ rhs: NSManagedObject, container: NSPersistentCloudKitContainer?
    ) -> Bool {
        let lhsID = idString(of: lhs)
        let rhsID = idString(of: rhs)
        switch (lhsID, rhsID) {
        case let (.some(left), .some(right)) where left != right:
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return recordNameThenURIPrecedes(lhs, rhs, container: container)
        }
    }

    /// The tie-break every ordering ends on: the lower CloudKit record name (a
    /// copy in iCloud before one that isn't), then the object URI, reached only
    /// when neither copy has been sent, so it exists on this device alone.
    static func recordNameThenURIPrecedes(
        _ lhs: NSManagedObject, _ rhs: NSManagedObject, container: NSPersistentCloudKitContainer?
    ) -> Bool {
        let lhsName = DedupSyncState.recordName(of: lhs.objectID, container: container)
        let rhsName = DedupSyncState.recordName(of: rhs.objectID, container: container)
        switch (lhsName, rhsName) {
        case let (.some(left), .some(right)) where left != right:
            return left < right
        case (.some, .none):
            return true
        case (.none, .some):
            return false
        default:
            return lhs.objectID.uriRepresentation().absoluteString
                < rhs.objectID.uriRepresentation().absoluteString
        }
    }

    private static func idString(of object: NSManagedObject) -> String? {
        guard object.entity.attributesByName["id"] != nil else { return nil }
        return (object.value(forKey: "id") as? UUID)?.uuidString
    }

    /// Saves what a cleanup step folded. A failed save is rolled back (#62):
    /// left in the context, its deletes and merges rode along half-done on the
    /// next step's save, or made every later save of the pass fail too. The
    /// next pass tries again. Returns whether the folds stand.
    @discardableResult
    static func saveFolds(in context: NSManagedObjectContext) -> Bool {
        if context.safeSave() { return true }
        logger.error("A duplicate cleanup could not save; its changes were taken back for the next pass")
        context.rollback()
        return false
    }
}
