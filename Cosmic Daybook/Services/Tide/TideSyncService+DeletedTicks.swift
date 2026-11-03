// TideSyncService+DeletedTicks.swift
// Linked to-dos deleted while ticked, read from the change notification
// before they are gone (bug hunt 2026-11-02 #11).

import CoreData
import Foundation

extension TideSyncService {
    /// Linked to-dos deleted here while ticked (Clear Completed, say), with
    /// their links: the engine keeps a tick that hasn't reached Tide yet, so
    /// it still goes. Only objects still in memory are read; a delete that
    /// arrives from iCloud has no values, and the engine knows that tick from
    /// the run that saw it ticked.
    /// Read on the context's own (main) queue, as the notification is posted.
    nonisolated static func deletedTicks(in userInfo: [AnyHashable: Any]?) -> [(id: UUID, link: String)] {
        guard let deleted = userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> else { return [] }
        return deleted.compactMap { object -> (id: UUID, link: String)? in
            guard let todo = object as? CDTodoItem, !todo.isFault, todo.isCompleted,
                  let id = todo.id, let link = todo.tideLink else { return nil }
            return (id, link)
        }
    }
}
