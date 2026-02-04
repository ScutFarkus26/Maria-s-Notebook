import Foundation
import SwiftData

/// Represents a collaborative practice session where one or more students work together
/// on their assigned work items. This enables tracking group practice dynamics,
/// shared observations, and practice partnerships over time.
@Model
final class PracticeSession: Identifiable {
    // MARK: - Identity & Timestamps
    
    /// Unique identifier for the practice session
    var id: UUID = UUID()
    
    /// When this practice session record was created
    var createdAt: Date = Date()
    
    /// When the practice session actually occurred
    var date: Date = Date()
    
    // MARK: - Session Details
    
    /// Duration of the practice session in seconds (optional)
    var duration: TimeInterval? = nil
    
    /// Student IDs who participated in this practice session (CloudKit compatible strings)
    var studentIDs: [String] = []
    
    /// Work item IDs that were practiced during this session (CloudKit compatible strings)
    var workItemIDs: [String] = []
    
    /// Shared observations and notes about the group practice session
    var sharedNotes: String = ""
    
    /// Location or context where practice occurred (e.g., "Small table", "Outside", "Library corner")
    var location: String? = nil
    
    // MARK: - Relationships
    
    /// Rich notes attached to this practice session (with multi-student scope support)
    @Relationship(deleteRule: .cascade, inverse: \Note.practiceSession)
    var notes: [Note]? = []
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        date: Date = Date(),
        duration: TimeInterval? = nil,
        studentIDs: [String] = [],
        workItemIDs: [String] = [],
        sharedNotes: String = "",
        location: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.date = AppCalendar.startOfDay(date)
        self.duration = duration
        self.studentIDs = studentIDs
        self.workItemIDs = workItemIDs
        self.sharedNotes = sharedNotes
        self.location = location
    }
    
    // MARK: - Computed Properties
    
    /// Returns true if this is a group practice session (2+ students)
    var isGroupSession: Bool {
        studentIDs.count > 1
    }
    
    /// Returns true if this is a solo practice session (1 student)
    var isSoloSession: Bool {
        studentIDs.count == 1
    }
    
    /// Number of students who participated
    var participantCount: Int {
        studentIDs.count
    }
    
    /// Number of work items practiced
    var workItemCount: Int {
        workItemIDs.count
    }
    
    /// Formatted duration string (e.g., "30 min", "1.5 hrs")
    var durationFormatted: String? {
        guard let duration = duration else { return nil }
        let minutes = Int(duration / 60)
        if minutes < 60 {
            return "\(minutes) min"
        } else {
            let hours = Double(minutes) / 60.0
            return String(format: "%.1f hrs", hours)
        }
    }
    
    // MARK: - Helper Methods
    
    /// Checks if a specific student participated in this session
    func includes(studentID: UUID) -> Bool {
        studentIDs.contains(studentID.uuidString)
    }
    
    /// Checks if a specific work item was practiced in this session
    func includes(workItemID: UUID) -> Bool {
        workItemIDs.contains(workItemID.uuidString)
    }
    
    /// Returns student UUIDs from the stored string IDs
    var studentUUIDs: [UUID] {
        studentIDs.compactMap { UUID(uuidString: $0) }
    }
    
    /// Returns work item UUIDs from the stored string IDs
    var workItemUUIDs: [UUID] {
        workItemIDs.compactMap { UUID(uuidString: $0) }
    }
    
    /// Adds a student to the practice session if not already present
    func addStudent(_ studentID: UUID) {
        let idString = studentID.uuidString
        if !studentIDs.contains(idString) {
            studentIDs.append(idString)
        }
    }
    
    /// Adds a work item to the practice session if not already present
    func addWorkItem(_ workItemID: UUID) {
        let idString = workItemID.uuidString
        if !workItemIDs.contains(idString) {
            workItemIDs.append(idString)
        }
    }
    
    /// Removes a student from the practice session
    func removeStudent(_ studentID: UUID) {
        let idString = studentID.uuidString
        studentIDs.removeAll { $0 == idString }
    }
    
    /// Removes a work item from the practice session
    func removeWorkItem(_ workItemID: UUID) {
        let idString = workItemID.uuidString
        workItemIDs.removeAll { $0 == idString }
    }
}
