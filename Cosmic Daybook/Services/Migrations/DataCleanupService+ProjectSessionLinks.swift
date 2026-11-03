import Foundation
import CoreData
import os

// MARK: - Project Sessions Back on Their Projects

nonisolated extension DataCleanupService {

    /// Links each project session that names its project (`projectID`) but
    /// isn't linked to it (`project == nil`) back to that project.
    ///
    /// Restore set only the `projectID` string until 2026-11-02, and every
    /// screen reads sessions through the relationship: after a Replace, or a
    /// Merge that brought sessions this device lacked, book clubs and
    /// projects showed no sessions, a project with only restored sessions
    /// looked inactive, and a restored session's page showed no members (bug
    /// hunt 2026-11-02, #7). The importer now links them; this puts back the
    /// ones earlier restores left. Only a session with no project whose id
    /// names a project in the same store is touched (sessions and projects
    /// are the guide's own, in the private store); one naming no project here
    /// yet is left for a later run. It only fills an empty link, with the
    /// same project everywhere, so two devices converge.
    ///
    /// Returns how many sessions it linked. Synchronous, on `context`'s
    /// queue; it doesn't save.
    @discardableResult
    static func relinkUnlinkedProjectSessions(using context: NSManagedObjectContext) -> Int {
        let request = CDFetchRequest(CDProjectSession.self)
        request.predicate = NSPredicate(format: "project == nil AND projectID != ''")
        let sessions = context.safeFetch(request).filter { !$0.isDeleted }
        let projectIDs = Set(sessions.compactMap { UUID(uuidString: $0.projectID) })
        guard !projectIDs.isEmpty else { return 0 }

        let projectRequest = CDFetchRequest(CDProject.self)
        projectRequest.predicate = NSPredicate(format: "id IN %@", Array(projectIDs))
        var projectsByID: [UUID: CDProject] = [:]
        for project in context.safeFetch(projectRequest) where !project.isDeleted {
            if let id = project.id, projectsByID[id] == nil { projectsByID[id] = project }
        }

        var linked = 0
        for session in sessions {
            guard let id = UUID(uuidString: session.projectID), let project = projectsByID[id],
                  project.objectID.persistentStore === session.objectID.persistentStore else { continue }
            session.project = project
            linked += 1
        }
        if linked > 0 {
            logger.info("Linked \(linked, privacy: .public) project session(s) back to their project")
        }
        return linked
    }

    /// Runs `relinkUnlinkedProjectSessions` from the launch pass, every launch
    /// (after the first run its fetch finds nothing): never while the first
    /// download from iCloud is under way (`FirstDownloadGate`), since a
    /// session can land before its project, and never on a pass whose earlier
    /// steps left changes they couldn't save. No done flag, so nothing can
    /// mark it done on a store that isn't all there. It saves its own changes.
    ///
    /// Returns how many sessions it linked, or nil when it didn't run or couldn't save.
    @discardableResult
    static func relinkUnlinkedProjectSessionsIfDue(
        using context: NSManagedObjectContext,
        firstDownloadPending: Bool
    ) -> Int? {
        guard !firstDownloadPending, !context.hasChanges else { return nil }
        let linked = relinkUnlinkedProjectSessions(using: context)
        guard !context.hasChanges || context.safeSave() else {
            context.rollback()
            return nil
        }
        return linked
    }
}
