import Foundation
import OSLog
import CoreData

/// Repository for managing CDPracticeSession CRUD operations
struct PracticeSessionRepository: Repository {
    typealias Model = CDPracticeSession

    private static let logger = Logger.work

    let context: NSManagedObjectContext

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

    /// Fetches a specific practice session by ID
    func fetch(byID id: UUID) -> CDPracticeSession? { fetch(id: id) }

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

}
