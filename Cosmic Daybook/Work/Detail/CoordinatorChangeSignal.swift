//
//  CoordinatorChangeSignal.swift
//  Cosmic Daybook
//
//  A change signal for entities the history processor doesn't report
//  (`onPresentationDataChange` covers only its own list): an edit on the
//  screen's context, or a save on another context of the same store
//  coordinator. Practice sessions and the presentation history's notes use it.
//

import Combine
import CoreData
import Foundation

enum CoordinatorChangeSignal {

    /// One of `entityNames` inserted, edited or deleted where a whole-table
    /// fetch on `context` would have seen it: an edit or merge on `context`,
    /// or a save on another context of its store coordinator (which reaches
    /// `context` only for the objects it has registered, so a session that
    /// newly names this work or child would otherwise be missed; a save in
    /// another store cannot touch this screen). Delivered on the main queue.
    nonisolated static func changes(
        of entityNames: Set<String>,
        in context: NSManagedObjectContext
    ) -> some Publisher<Void, Never> {
        let center = NotificationCenter.default
        let contextID = ObjectIdentifier(context)
        let coordinatorID = context.persistentStoreCoordinator.map(ObjectIdentifier.init)
        let otherSaves = center.publisher(for: .NSManagedObjectContextDidSave).filter { note in
            // Posted on the saver's own queue, so reading it here is safe.
            guard let saver = note.object as? NSManagedObjectContext else { return true }
            // This context's own saves were already seen as edits.
            if ObjectIdentifier(saver) == contextID { return false }
            guard let coordinatorID, let theirs = saver.persistentStoreCoordinator else { return true }
            return ObjectIdentifier(theirs) == coordinatorID
        }
        return center.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)
            .merge(with: otherSaves)
            .filter { !ManagedObjectChangeScope.touched(entityNames, in: $0.userInfo).isEmpty }
            .map { _ in () }
            .receive(on: DispatchQueue.main)
    }

    /// `changes(of:in:)`, one delivery `interval` after the last. A save on
    /// another context arrives twice (its own notification, then the merge
    /// into `context` of the objects this screen holds), and an import or a
    /// bulk edit many times back to back; a screen that re-reads a whole table
    /// on the signal does it once (review of bug hunt 2026-10-17 #48, the
    /// Progress dashboard's 250 ms). Delivered on the main queue.
    nonisolated static func coalescedChanges(
        of entityNames: Set<String>,
        in context: NSManagedObjectContext,
        interval: DispatchQueue.SchedulerTimeType.Stride = .milliseconds(250)
    ) -> some Publisher<Void, Never> {
        changes(of: entityNames, in: context)
            .debounce(for: interval, scheduler: DispatchQueue.main)
    }
}
