import CoreData
import OSLog

/// Deletes a project with everything that hangs off it: its sessions, the work
/// those sessions assigned, and its roles. Leaves saving to the caller.
enum ProjectDeletion {
    private static let logger = Logger.projects

    static func delete(_ club: CDProject, in modelContext: NSManagedObjectContext) {
        // OPTIMIZATION: Use targeted filtering instead of loading all records upfront
        // SwiftData predicates can't compare captured UUID values, so we fetch and filter
        // This is still more efficient than the original which loaded everything into @Query properties

        let clubID = club.id ?? UUID()

        // Delete sessions and their related work contracts
        // Fetch all sessions (can't use predicate with captured UUID), then filter
        let clubIDString = clubID.uuidString
        let allSessions: [CDProjectSession]
        do {
            allSessions = try modelContext.fetch(CDFetchRequest(CDProjectSession.self))
        } catch {
            logger.warning("Failed to fetch project sessions: \(error)")
            allSessions = []
        }
        let sessions = allSessions.filter { $0.projectID == clubIDString }

        // Fetch work models only for these sessions
        let sessionIDs = Set(sessions.compactMap { $0.id?.uuidString })
        let allWorkModels: [CDWorkModel]
        do {
            allWorkModels = try modelContext.fetch(CDFetchRequest(CDWorkModel.self))
        } catch {
            logger.warning("Failed to fetch work models: \(error)")
            allWorkModels = []
        }
        let workModels = allWorkModels.filter {
            ($0.sourceContextType == .projectSession || $0.sourceContextType == .bookClubSession) &&
            sessionIDs.contains($0.sourceContextID ?? "")
        }

        // Through the service, so check-ins keyed only by workID string,
        // completion records and passenger rows on linked copies go too.
        if !workModels.isEmpty {
            do {
                try WorkDeletionService(context: modelContext).delete(workModels) { true }
            } catch {
                logger.error("Failed to delete club work: \(error)")
            }
        }
        for s in sessions {
            modelContext.delete(s)
        }

        // Delete roles for this club
        let allRoles: [CDProjectRole]
        do {
            allRoles = try modelContext.fetch(CDFetchRequest(CDProjectRole.self))
        } catch {
            logger.warning("Failed to fetch project roles: \(error)")
            allRoles = []
        }
        let roles = allRoles.filter { $0.projectID == clubIDString }
        for r in roles { modelContext.delete(r) }

        deleteTemplateRows(of: club, id: clubIDString, in: modelContext)

        // Finally, delete the club itself
        modelContext.delete(club)
    }

    /// The project's template weeks, the role assignments on them and its
    /// assignment templates. Nothing writes these any more, but a project
    /// made before they were retired still has them, and they are the
    /// project's alone: left behind, every backup carried them (bug hunt
    /// 2026-10-17, #44).
    private static func deleteTemplateRows(
        of club: CDProject, id clubID: String, in context: NSManagedObjectContext
    ) {
        let weeks = CDFetchRequest(CDProjectTemplateWeek.self)
        weeks.predicate = NSPredicate(format: "projectID ==[c] %@", clubID)
        let doomedWeeks = context.safeFetch(weeks)
        let weekIDs = Set(doomedWeeks.compactMap { $0.id?.uuidString.lowercased() })
        let weekObjects = Set(doomedWeeks.map(\.objectID))

        // Few rows, and matched by either link, so in memory.
        for assignment in context.safeFetch(CDFetchRequest(CDProjectWeekRoleAssignment.self))
        where weekIDs.contains(assignment.weekID.lowercased())
            || assignment.week.map({ weekObjects.contains($0.objectID) }) == true {
            context.delete(assignment)
        }
        for week in doomedWeeks { context.delete(week) }

        let templates = CDFetchRequest(CDProjectAssignmentTemplate.self)
        templates.predicate = NSPredicate(format: "projectID ==[c] %@ OR project == %@", clubID, club)
        for template in context.safeFetch(templates) { context.delete(template) }
    }
}
