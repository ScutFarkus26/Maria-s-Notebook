import Foundation
import OSLog
import SwiftData

/// Repository for managing PracticeSession CRUD operations
struct PracticeSessionRepository {
    private static let logger = Logger.work

    let modelContext: ModelContext

    // MARK: - Helper Methods

    private func safeFetch<T>(_ descriptor: FetchDescriptor<T>, context: String = #function) -> [T] {
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Self.logger.warning("\(context): Failed to fetch \(T.self): \(error)")
            return []
        }
    }

    private func safeFetchFirst<T>(_ descriptor: FetchDescriptor<T>, context: String = #function) -> T? {
        do {
            return try modelContext.fetch(descriptor).first
        } catch {
            Self.logger.warning("\(context): Failed to fetch \(T.self): \(error)")
            return nil
        }
    }

    private func safeSave(context: String = #function) {
        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("\(context): Failed to save: \(error)")
        }
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
    ) -> PracticeSession {
        let session = PracticeSession(
            date: date,
            duration: duration,
            studentIDs: studentIDs.map(\.uuidString),
            workItemIDs: workItemIDs.map(\.uuidString),
            sharedNotes: sharedNotes,
            location: location
        )
        modelContext.insert(session)
        safeSave()
        return session
    }
    
    // MARK: - Read
    
    /// Fetches all practice sessions
    func fetchAll() -> [PracticeSession] {
        let descriptor = FetchDescriptor<PracticeSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return safeFetch(descriptor)
    }
    
    /// Fetches practice sessions for a specific student
    func fetch(forStudentID studentID: UUID) -> [PracticeSession] {
        let idString = studentID.uuidString
        let descriptor = FetchDescriptor<PracticeSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let allSessions = safeFetch(descriptor)
        return allSessions.filter { $0.studentIDs.contains(idString) }
    }
    
    /// Fetches practice sessions for a specific work item
    func fetch(forWorkItemID workItemID: UUID) -> [PracticeSession] {
        let idString = workItemID.uuidString
        let descriptor = FetchDescriptor<PracticeSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        let allSessions = safeFetch(descriptor)
        return allSessions.filter { $0.workItemIDs.contains(idString) }
    }
    
    /// Fetches practice sessions within a date range
    func fetch(from startDate: Date, to endDate: Date) -> [PracticeSession] {
        let descriptor = FetchDescriptor<PracticeSession>(
            predicate: #Predicate<PracticeSession> { session in
                session.date >= startDate && session.date <= endDate
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return safeFetch(descriptor)
    }
    
    /// Fetches group practice sessions (2+ students)
    func fetchGroupSessions() -> [PracticeSession] {
        let allSessions = fetchAll()
        return allSessions.filter(\.isGroupSession)
    }
    
    /// Fetches solo practice sessions (1 student)
    func fetchSoloSessions() -> [PracticeSession] {
        let allSessions = fetchAll()
        return allSessions.filter(\.isSoloSession)
    }
    
    /// Fetches practice partnerships for a student (who they practiced with most)
    func fetchPartnerships(forStudentID studentID: UUID) -> [(partnerID: UUID, sessionCount: Int)] {
        let sessions = fetch(forStudentID: studentID)
        var partnerCounts: [UUID: Int] = [:]
        
        for session in sessions where session.isGroupSession {
            for partnerIDString in session.studentIDs where partnerIDString != studentID.uuidString {
                if let partnerID = UUID(uuidString: partnerIDString) {
                    partnerCounts[partnerID, default: 0] += 1
                }
            }
        }
        
        return partnerCounts.map { ($0.key, $0.value) }
            .sorted { $0.1 > $1.1 } // Sort by session count descending
    }
    
    /// Fetches a specific practice session by ID
    func fetch(byID id: UUID) -> PracticeSession? {
        let descriptor = FetchDescriptor<PracticeSession>(
            predicate: #Predicate<PracticeSession> { session in
                session.id == id
            }
        )
        return safeFetchFirst(descriptor)
    }
    
    // MARK: - Update
    
    /// Updates an existing practice session
    func update(
        _ session: PracticeSession,
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
            session.studentIDs = studentIDs.map(\.uuidString)
        }
        if let workItemIDs {
            session.workItemIDs = workItemIDs.map(\.uuidString)
        }
        if let sharedNotes {
            session.sharedNotes = sharedNotes
        }
        if let location {
            session.location = location
        }
        safeSave()
    }
    
    // MARK: - Delete
    
    /// Deletes a practice session
    func delete(_ session: PracticeSession) {
        modelContext.delete(session)
        safeSave()
    }
    
    /// Deletes all practice sessions for a specific student
    func deleteAll(forStudentID studentID: UUID) {
        let sessions = fetch(forStudentID: studentID)
        for session in sessions {
            modelContext.delete(session)
        }
        safeSave()
    }
    
    // MARK: - Statistics
    
    /// Returns practice session statistics for a student
    func statistics(forStudentID studentID: UUID) -> PracticeStatistics {
        let sessions = fetch(forStudentID: studentID)
        let groupSessions = sessions.filter(\.isGroupSession)
        let soloSessions = sessions.filter(\.isSoloSession)
        
        let totalDuration = sessions.compactMap(\.duration).reduce(0, +)
        let averageDuration = sessions.compactMap(\.duration).isEmpty
            ? 0
            : totalDuration / Double(sessions.compactMap(\.duration).count)
        
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
