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
        CoordinatorChangeSignal.changes(of: noteEntityNames, in: context)
    }

    /// What a change to a presentation does to the history.
    enum AssignmentChangeResponse: Equatable {
        /// Draw the loaded page again: a given presentation was re-dated, or
        /// a child added or taken off, which the loaded rows already carry.
        case redraw
        /// Fetch the page again: one was given or taken back, or a given one
        /// the page doesn't hold was edited.
        case refetchPage
        /// Nothing here: a planned lesson moved, say.
        case ignore
    }

    /// Which presentations a change touched, as its notification said.
    nonisolated enum AssignmentTouches: Equatable, Sendable {
        case objects(Set<NSManagedObjectID>)
        /// A remote import names only the table, and "everything changed"
        /// names nothing.
        case unknown

        func merged(with other: AssignmentTouches) -> AssignmentTouches {
            guard case .objects(let mine) = self, case .objects(let theirs) = other else { return .unknown }
            return .objects(mine.union(theirs))
        }
    }

    /// A moved count, or a loaded row that is no longer a given presentation
    /// (deleted, or taken back while another was given), fetches the page
    /// again, as does a touched presentation that is given but not on the
    /// page (an MCP or synced re-date can move one into it). A touched row
    /// on the page is drawn again, since rows change in place (a re-date, a
    /// child added) without the count moving; a change to anything else is
    /// left alone (review of bug hunt 2026-10-17 #45). When the notification
    /// doesn't say which (`unknown`), or the count fails (nil), what is
    /// loaded is drawn again.
    static func assignmentChangeResponse(
        touches: AssignmentTouches = .unknown,
        loadedIDs: Set<NSManagedObjectID> = [],
        isGiven: (NSManagedObjectID) -> Bool = { _ in false },
        newCount: Int?,
        lastCount: Int,
        loadedRowsStillGiven: Bool = true
    ) -> AssignmentChangeResponse {
        if !loadedRowsStillGiven { return .refetchPage }
        if let newCount, newCount != lastCount { return .refetchPage }
        guard case .objects(let ids) = touches else { return .redraw }
        if ids.contains(where: { !loadedIDs.contains($0) && isGiven($0) }) { return .refetchPage }
        return ids.isDisjoint(with: loadedIDs) ? .ignore : .redraw
    }

    /// Whether `objectID` is a given presentation as `context` reads it now;
    /// false for one deleted or gone.
    static func isGivenPresentation(_ objectID: NSManagedObjectID, in context: NSManagedObjectContext) -> Bool {
        guard let assignment = try? context.existingObject(with: objectID) as? CDLessonAssignment else {
            return false
        }
        return !assignment.isDeleted && assignment.isPresented
    }

    /// The presentations touched wherever the history could see it: an edit
    /// or merge on `context`, a save on another context of its store
    /// coordinator, or a remote import the history processor reports (which
    /// names only the table). Delivered on the main queue.
    nonisolated static func assignmentTouches(
        in context: NSManagedObjectContext
    ) -> some Publisher<AssignmentTouches, Never> {
        let center = NotificationCenter.default
        let contextID = ObjectIdentifier(context)
        let coordinatorID = context.persistentStoreCoordinator.map(ObjectIdentifier.init)
        let namesKey = PersistentHistoryProcessor.changedEntityNamesKey
        let edits = center.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)
            .compactMap { @Sendable note in touchedAssignments(in: note.userInfo) }
        let otherSaves = center.publisher(for: .NSManagedObjectContextDidSave)
            .filter { @Sendable note in
                // Posted on the saver's own queue, so reading it here is safe.
                guard let saver = note.object as? NSManagedObjectContext,
                      ObjectIdentifier(saver) != contextID,
                      let coordinatorID, let theirs = saver.persistentStoreCoordinator else { return false }
                return ObjectIdentifier(theirs) == coordinatorID
            }
            .compactMap { @Sendable note in touchedAssignments(in: note.userInfo) }
        let imports = center.publisher(for: .presentationDataDidChange)
            .compactMap { @Sendable note -> AssignmentTouches? in
                guard let changed = note.userInfo?[namesKey] as? Set<String>,
                      changed.contains(assignmentEntityName) else { return nil }
                return .unknown
            }
        return edits.merge(with: otherSaves, imports).receive(on: DispatchQueue.main)
    }

    /// The presentations `userInfo` reports; nil when it reports none.
    /// Reads only `objectID`s, which are safe from any thread.
    nonisolated private static func touchedAssignments(in userInfo: [AnyHashable: Any]?) -> AssignmentTouches? {
        guard let userInfo else { return nil }
        if userInfo[NSInvalidatedAllObjectsKey] != nil { return .unknown }
        var ids: Set<NSManagedObjectID> = []
        for key in [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey,
                    NSRefreshedObjectsKey, NSInvalidatedObjectsKey] {
            guard let objects = userInfo[key] as? Set<NSManagedObject> else { continue }
            for object in objects where object.objectID.entity.name == assignmentEntityName {
                ids.insert(object.objectID)
            }
        }
        return ids.isEmpty ? nil : .objects(ids)
    }

    nonisolated private static let assignmentEntityName = "LessonAssignment"

    /// Answers the presentation changes gathered since the last answer.
    func respondToAssignmentChanges() {
        guard let touches = pendingAssignmentTouches else { return }
        pendingAssignmentTouches = nil
        let newCount = Self.presentedAssignmentCount(in: viewContext)
        let context = viewContext
        switch Self.assignmentChangeResponse(
            touches: touches,
            loadedIDs: Set(loadedAssignments.map(\.objectID)),
            isGiven: { Self.isGivenPresentation($0, in: context) },
            newCount: newCount,
            lastCount: lastAssignmentCount,
            loadedRowsStillGiven: loadedRowsStillGiven
        ) {
        case .refetchPage:
            lastAssignmentCount = newCount ?? lastAssignmentCount
            loadAssignments(
                limit: loadedAssignments.count >= Self.initialLoadCount ? nil : Self.initialLoadCount
            )
        case .redraw:
            assignmentRevision &+= 1
        case .ignore:
            break
        }
    }

    /// Whether every loaded row is still a given presentation in this context.
    var loadedRowsStillGiven: Bool {
        !loadedAssignments.contains { $0.isDeleted || $0.managedObjectContext == nil || !$0.isPresented }
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
