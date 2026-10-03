//
//  PresentationRecordIndex+Background.swift
//  Cosmic Daybook
//
//  The whole-record index, read and folded off the main thread.
//
//  Today's ready queue rebuilds the whole-record index after any change to
//  its inputs, and at the April backup's size the read and the fold are most
//  of that rebuild. Since the column read (`+Rows`) neither needs nor
//  registers a managed object, nothing ties it to the view context: this reads
//  the same rows on a private-queue context of its own on the same
//  coordinator, folds them there, and hands back the value, which is
//  `Sendable`.
//
//  It stands in for `init(students:in:)` only when that call would take the
//  column read — a whole-record build on a view context that reads straight
//  from its coordinator and holds no unsaved edit to the three entities — so
//  it reads what that call reads. A context of its own has nothing pending, so
//  `readRows` takes the column read here too, and falls back to the object
//  read on this context if a column fetch fails, as it does anywhere else.
//

import CoreData
import Foundation

nonisolated extension PresentationRecordIndex {

    /// The whole-record index over `students` (`nil` keeps everyone), read
    /// and folded on a new private-queue context on `coordinator`.
    ///
    /// `@concurrent`, so the block is handed to that context from the
    /// concurrent executor at the calling task's priority, never from the
    /// main thread.
    @concurrent
    static func readInBackground(
        students: Set<String>?,
        from coordinator: NSPersistentStoreCoordinator
    ) async -> PresentationRecordIndex {
        let context = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        context.name = "PresentationRecordIndex.readInBackground"
        return await context.perform {
            #if DEBUG
            dispatchPrecondition(condition: .notOnQueue(.main))
            #endif
            return PresentationRecordIndex(students: students, in: context)
        }
    }
}
