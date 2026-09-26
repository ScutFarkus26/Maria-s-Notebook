//
//  LessonAssignmentHistoryView+ChangeDetection.swift
//  Cosmic Daybook
//
//  The counts the history reloads on, taken with count(for:) when their
//  tables change instead of kept live by two whole-table fetch requests
//  (every note, every presented assignment), and the note-change signal
//  that says when to take them.
//

import Combine
import CoreData
import Foundation
import OSLog

extension LessonAssignmentHistoryView {

    /// Presented assignments, the rows this history lists, with the old
    /// fetch's predicate (unsaved edits in `context` included, as that fetch
    /// saw them); nil when the count fails (logged).
    static func presentedAssignmentCount(in context: NSManagedObjectContext) -> Int? {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "stateRaw == %@", LessonAssignmentState.presented.rawValue)
        return count(request, in: context)
    }

    /// Every note, as the old notes fetch held them; nil when the count
    /// fails (logged).
    static func noteCount(in context: NSManagedObjectContext) -> Int? {
        count(CDFetchRequest(CDNote.self), in: context)
    }

    /// The notes `buildCachesAsync` counts per presentation, with their
    /// presentations prefetched. It reads only each note's presentation id,
    /// so leaving out the notes that have none gives the same counts as
    /// reading every note.
    static func assignmentNotes(in context: NSManagedObjectContext) -> [CDNote] {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(format: "lessonAssignment != nil")
        request.relationshipKeyPathsForPrefetching = ["lessonAssignment"]
        return context.safeFetch(request)
    }

    /// A note inserted, edited or deleted where the whole-table notes fetch
    /// would have seen it: an edit or merge on `context`, or a save on another
    /// context of its store coordinator (which reaches `context` only for the
    /// notes it has registered, and it no longer registers them all; a save
    /// in another store cannot move these counts). Delivered on the main queue.
    nonisolated static func noteChanges(in context: NSManagedObjectContext) -> some Publisher<Void, Never> {
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
        let watched = noteEntityNames
        return center.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)
            .merge(with: otherSaves)
            .filter { !ManagedObjectChangeScope.touched(watched, in: $0.userInfo).isEmpty }
            .map { _ in () }
            .receive(on: DispatchQueue.main)
    }

    /// Whether the note count moved since the caches were last built.
    var noteCountMoved: Bool {
        Self.noteCount(in: viewContext).map { $0 != lastNotesCount } ?? false
    }

    nonisolated private static let noteEntityNames: Set<String> = ["Note"]

    private static func count<T: NSManagedObject>(
        _ request: NSFetchRequest<T>, in context: NSManagedObjectContext
    ) -> Int? {
        do {
            return try context.count(for: request)
        } catch {
            Logger.presentations.warning("Failed to count \(String(describing: T.self)): \(error)")
            return nil
        }
    }
}
