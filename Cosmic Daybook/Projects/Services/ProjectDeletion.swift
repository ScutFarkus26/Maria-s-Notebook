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

        // Finally, delete the club itself
        modelContext.delete(club)
    }
}
