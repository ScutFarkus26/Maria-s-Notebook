// PresentationsViewModel+AssignmentGate.swift
// Knows when the cached assignment table can stand in for a refetch.

import CoreData
import Foundation

extension PresentationsViewModel {
    /// Starts watching `context` for assignment changes (once per context).
    /// Mirrors `View.onPresentationDataChange`: edits on the context itself,
    /// saves on any other context, and remote imports the history processor
    /// reports. A context reset counts as a change.
    func observeAssignmentChanges(in context: NSManagedObjectContext) {
        guard observedContext !== context else { return }
        let center = NotificationCenter.default
        assignmentObservers.forEach(center.removeObserver)
        observedContext = context
        cachedAssignmentsGeneration = nil

        let names: Set<String> = ["LessonAssignment"]
        let contextID = ObjectIdentifier(context)
        let coordinatorID = context.persistentStoreCoordinator.map(ObjectIdentifier.init)
        let markDirty: @Sendable () -> Void = { [weak self] in
            if Thread.isMainThread {
                MainActor.assumeIsolated { self?.assignmentsGeneration &+= 1 }
            } else {
                Task { @MainActor in self?.assignmentsGeneration &+= 1 }
            }
        }
        assignmentObservers = [
            center.addObserver(
                forName: .NSManagedObjectContextObjectsDidChange, object: context, queue: nil
            ) { note in
                if !ManagedObjectChangeScope.touched(names, in: note.userInfo).isEmpty { markDirty() }
            },
            center.addObserver(forName: .NSManagedObjectContextDidSave, object: nil, queue: nil) { note in
                guard let saved = note.object as AnyObject?, ObjectIdentifier(saved) != contextID else { return }
                if Self.savedAssignment(in: note.userInfo, coordinator: coordinatorID) { markDirty() }
            },
            center.addObserver(forName: .presentationDataDidChange, object: nil, queue: nil) { note in
                let key = PersistentHistoryProcessor.changedEntityNamesKey
                guard let changed = note.userInfo?[key] as? Set<String>, changed.contains("LessonAssignment") else {
                    return
                }
                markDirty()
            }
        ]
    }

    /// True when a save reported a `LessonAssignment` that could live in this
    /// coordinator's stores. A save in another workspace (Sample Class, the
    /// Assistant's store) cannot change what this model shows. An object
    /// whose id names no store yet (a temporary id) or a context reset
    /// counts, so nothing the view context can see is missed. Reads only
    /// `objectID`s, which are safe on the posting thread.
    nonisolated static func savedAssignment(
        in userInfo: [AnyHashable: Any]?,
        coordinator: ObjectIdentifier?
    ) -> Bool {
        guard let userInfo else { return false }
        if userInfo[NSInvalidatedAllObjectsKey] != nil { return true }
        let keys = [
            NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey,
            NSRefreshedObjectsKey, NSInvalidatedObjectsKey
        ]
        for key in keys {
            guard let objects = userInfo[key] as? Set<NSManagedObject> else { continue }
            for object in objects where object.objectID.entity.name == "LessonAssignment" {
                guard let coordinator,
                      let store = object.objectID.persistentStore,
                      let storeCoordinator = store.persistentStoreCoordinator else { return true }
                if ObjectIdentifier(storeCoordinator) == coordinator { return true }
            }
        }
        return false
    }
}
