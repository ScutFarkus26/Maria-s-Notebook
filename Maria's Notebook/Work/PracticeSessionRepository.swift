import Foundation
import OSLog
import CoreData
import SwiftData

/// Repository for managing CDPracticeSession CRUD operations
struct PracticeSessionRepository {
    private static let logger = Logger.work

    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// Deprecated init for callers still passing ModelContext.
    @available(*, deprecated, message: "Pass NSManagedObjectContext instead of ModelContext")
    @MainActor
    init(modelContext: ModelContext) {
        self.context = AppBootstrapping.getSharedCoreDataStack().viewContext
    }

    // MARK: - Create

    /// Creates and saves a new practice session
    @discardableResult
    func create(
        date: Date = Date(),
        duration: TimeInterval? = nil,
        studentIDs: [UUID],
        workItemIDs: [UUID],
        sharedNotes: String = "",
        location: String? = nil
    ) -> CDPracticeSession {
        let session = CDPracticeSession(context: context)
        session.date = date
        session.duration = duration ?? 0
        session.studentIDs = studentIDs.map(\.uuidString) as NSArray
        session.workItemIDs = workItemIDs.map(\.uuidString) as NSArray
        session.sharedNotes = sharedNotes
        session.location = location
        context.safeSave()
        return session
    }

    // MARK: - Read

    /// Fetches all practice sessions
    func fetchAll() -> [CDPracticeSession] {
        let request = CDFetchRequest(CDPracticeSession.self)
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return context.safeFetch(request)
    }

    /// Fetches practice sessions for a specific student
    func fetch(forStudentID studentID: UUID) -> [CDPracticeSession] {
        let idString = studentID.uuidString
        let allSessions = fetchAll()
        return allSessions.filter { session in
            let ids = (session.studentIDs as? [String]) ?? []
            return ids.contains(idString)
        }
    }

    /// Fetches practice sessions for a specific work item
    func fetch(forWorkItemID workItemID: UUID) -> [CDPracticeSession] {
        let idString = workItemID.uuidString
        let allSessions = fetchAll()
        return allSessions.filter { session in
            let ids = (session.workItemIDs as? [String]) ?? []
            return ids.contains(idString)
        }
    }

    /// Fetches practice sessions within a date range
    func fetch(from startDate: Date, to endDate: Date) -> [CDPracticeSession] {
        let request = CDFetchRequest(CDPracticeSession.self)
        request.predicate = NSPredicate(
            format: "date >= %@ AND date <= %@",
            startDate as NSDate, endDate as NSDate
        )
        request.sortDescriptors = [NSSortDescriptor(key: "date", ascending: false)]
        return context.safeFetch(request)
    }

    /// Fetches group practice sessions (2+ students)
    func fetchGroupSessions() -> [CDPracticeSession] {
        let allSessions = fetchAll()
        return allSessions.filter { session in
            let ids = (session.studentIDs as? [String]) ?? []
            return ids.count >= 2
        }
    }

    /// Fetches solo practice sessions (1 student)
    func fetchSoloSessions() -> [CDPracticeSession] {
        let allSessions = fetchAll()
        return allSessions.filter { session in
            let ids = (session.studentIDs as? [String]) ?? []
            return ids.count == 1
        }
    }

    /// Fetches practice partnerships for a student (who they practiced with most)
    func fetchPartnerships(forStudentID studentID: UUID) -> [(partnerID: UUID, sessionCount: Int)] {
        let sessions = fetch(forStudentID: studentID)
        var partnerCounts: [UUID: Int] = [:]

        for session in sessions {
            let ids = (session.studentIDs as? [String]) ?? []
            guard ids.count >= 2 else { continue }
            for partnerIDString in ids where partnerIDString != studentID.uuidString {
                if let partnerID = UUID(uuidString: partnerIDString) {
                    partnerCounts[partnerID, default: 0] += 1
                }
            }
        }

        return partnerCounts.map { ($0.key, $0.value) }
            .sorted { $0.1 > $1.1 }
    }

    /// Fetches a specific practice session by ID
    func fetch(byID id: UUID) -> CDPracticeSession? {
        let request = CDFetchRequest(CDPracticeSession.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return context.safeFetchFirst(request)
    }

    // MARK: - Update

    /// Updates an existing practice session
    func update(
        _ session: CDPracticeSession,
        date: Date? = nil,
        duration: TimeInterval? = nil,
        studentIDs: [UUID]? = nil,
        workItemIDs: [UUID]? = nil,
        sharedNotes: String? = nil,
        location: String? = nil
    ) {
        if let date {
            session.date = AppCalendar.startOfDay(date)
        }
        if let duration {
            session.duration = duration
        }
        if let studentIDs {
            session.studentIDs = studentIDs.map(\.uuidString) as NSArray
        }
        if let workItemIDs {
            session.workItemIDs = workItemIDs.map(\.uuidString) as NSArray
        }
        if let sharedNotes {
            session.sharedNotes = sharedNotes
        }
        if let location {
            session.location = location
        }
        context.safeSave()
    }

    // MARK: - Delete

    /// Deletes a practice session
    func delete(_ session: CDPracticeSession) {
        context.delete(session)
        context.safeSave()
    }

    /// Deletes all practice sessions for a specific student
    func deleteAll(forStudentID studentID: UUID) {
        let sessions = fetch(forStudentID: studentID)
        for session in sessions {
            context.delete(session)
        }
        context.safeSave()
    }

    // MARK: - Statistics

    /// Returns practice session statistics for a student
    func statistics(forStudentID studentID: UUID) -> PracticeStatistics {
        let sessions = fetch(forStudentID: studentID)
        let groupSessions = sessions.filter { session in
            let ids = (session.studentIDs as? [String]) ?? []
            return ids.count >= 2
        }
        let soloSessions = sessions.filter { session in
            let ids = (session.studentIDs as? [String]) ?? []
            return ids.count == 1
        }

        let durations = sessions.map(\.duration).filter { $0 > 0 }
        let totalDuration = durations.reduce(0, +)
        let averageDuration = durations.isEmpty ? 0 : totalDuration / Double(durations.count)

        return PracticeStatistics(
            totalSessions: sessions.count,
            groupSessions: groupSessions.count,
            soloSessions: soloSessions.count,
            totalDuration: totalDuration,
            averageDuration: averageDuration
        )
    }
}

// MARK: - Supporting Types

/// Statistics about practice sessions
struct PracticeStatistics {
    let totalSessions: Int
    let groupSessions: Int
    let soloSessions: Int
    let totalDuration: TimeInterval
    let averageDuration: TimeInterval

    var groupPercentage: Double {
        guard totalSessions > 0 else { return 0 }
        return Double(groupSessions) / Double(totalSessions) * 100
    }

    var soloPercentage: Double {
        guard totalSessions > 0 else { return 0 }
        return Double(soloSessions) / Double(totalSessions) * 100
    }

    var totalDurationFormatted: String {
        let hours = Int(totalDuration / 3600)
        let minutes = Int((totalDuration.truncatingRemainder(dividingBy: 3600)) / 60)
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }

    var averageDurationFormatted: String {
        let minutes = Int(averageDuration / 60)
        return "\(minutes) min"
    }
}
