import Foundation

/// Protocol for SwiftData models that maintain denormalized scheduling and student grouping fields.
///
/// `LessonAssignment` stores denormalized copies of scheduling dates
/// and student group keys for efficient predicate filtering. This protocol provides shared
/// default implementations so the synchronization logic lives in one place.
///
/// Conforming types must expose their stored properties and relationship data through the
/// required properties. The protocol extension then provides:
/// - `normalizeDenormalizedFields()` — syncs `scheduledForDay` from `scheduledFor`
/// - `updateDenormalizedKeys()` — rebuilds `studentGroupKeyPersisted` from resolved UUIDs
/// - `syncSnapshotsFromRelationships()` — copies relationship data into string-based fields
/// - `resolvedLessonID` — falls back from relationship to stored string ID
/// - `studentGroupKey` — falls back from persisted key to computed key
protocol DenormalizedSchedulable: AnyObject {
    // MARK: - Scheduling (stored properties)

    var scheduledFor: Date? { get set }
    var scheduledForDay: Date { get set }

    // MARK: - Student Grouping (stored properties)

    var studentGroupKeyPersisted: String { get set }

    // MARK: - Relationship Snapshots (stored properties)

    var lessonID: String { get set }
    var studentIDs: [String] { get set }

    // MARK: - Resolved Data (computed)

    /// Student UUIDs resolved from relationships (preferred) or stored string IDs (fallback).
    var resolvedStudentIDs: [UUID] { get }

    // MARK: - Bridge Properties (expose relationship data for defaults)

    /// The lesson relationship's UUID, if the relationship is loaded.
    var lessonRelationshipID: UUID? { get }

    /// Student IDs from the relationship array, as CloudKit-compatible strings.
    var studentRelationshipIDStrings: [String] { get }
}

// MARK: - Default Implementations

extension DenormalizedSchedulable {
    /// Syncs `scheduledForDay` to match `scheduledFor`, using start-of-day normalization.
    /// Call after any change to `scheduledFor` to keep the denormalized field in sync.
    func normalizeDenormalizedFields() {
        if let s = scheduledFor {
            scheduledForDay = AppCalendar.startOfDay(s)
        } else {
            scheduledForDay = Date.distantPast
        }
    }

    /// Rebuilds `studentGroupKeyPersisted` from sorted resolved student UUIDs.
    /// Call after any change to the student set to keep the denormalized key in sync.
    func updateDenormalizedKeys() {
        let ids = resolvedStudentIDs.sorted { $0.uuidString < $1.uuidString }
        studentGroupKeyPersisted = ids.map(\.uuidString).joined(separator: ",")
    }

    /// Copies relationship data into string-based snapshot fields for CloudKit compatibility.
    /// Call after attaching or modifying relationships to keep snapshot fields in sync.
    func syncSnapshotsFromRelationships() {
        if let relID = lessonRelationshipID {
            lessonID = relID.uuidString
        }
        studentIDs = studentRelationshipIDStrings
        updateDenormalizedKeys()
    }

    /// Lesson UUID resolved from relationship (preferred) or stored string ID (fallback).
    var resolvedLessonID: UUID {
        lessonRelationshipID ?? (UUID(uuidString: lessonID) ?? UUID())
    }

    /// Order-insensitive key for quick equality/group checks.
    /// Prefers the persisted key; falls back to computing from resolved student IDs.
    var studentGroupKey: String {
        if !studentGroupKeyPersisted.isEmpty { return studentGroupKeyPersisted }
        let ids = resolvedStudentIDs.sorted { $0.uuidString < $1.uuidString }
        return ids.map(\.uuidString).joined(separator: ",")
    }
}
