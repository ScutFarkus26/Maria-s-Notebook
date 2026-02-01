//
//  LessonAssignment.swift
//  Maria's Notebook
//
//  Created as part of StudentLesson + Presentation consolidation migration.
//

import Foundation
import SwiftData

/// Unified model for lesson planning and presentation history.
/// Replaces the previous two-model system (StudentLesson + Presentation).
///
/// Lifecycle: draft -> scheduled -> presented
/// - draft: Lesson assigned to students but not yet scheduled
/// - scheduled: Has a scheduled date for presentation
/// - presented: Has been given to students (immutable historical record)
@Model
final class LessonAssignment: Identifiable {
    // MARK: - Identity & Timestamps

    var id: UUID = UUID()
    var createdAt: Date = Date()
    var modifiedAt: Date = Date()

    // MARK: - State Machine

    /// Current state in the lifecycle. Use `state` computed property for type-safe access.
    var stateRaw: String = LessonAssignmentState.draft.rawValue

    /// Type-safe state accessor.
    var state: LessonAssignmentState {
        get { LessonAssignmentState(rawValue: stateRaw) ?? .draft }
        set { stateRaw = newValue.rawValue }
    }

    // MARK: - Scheduling

    /// When the lesson is scheduled to be presented. Nil for drafts.
    var scheduledFor: Date? {
        didSet {
            if let date = scheduledFor {
                scheduledForDay = AppCalendar.startOfDay(date)
            } else {
                scheduledForDay = Date.distantPast
            }
        }
    }

    /// Denormalized start-of-day for efficient querying and sorting.
    var scheduledForDay: Date = Date.distantPast

    // MARK: - Presentation Record

    /// When the lesson was actually presented. Nil until state becomes .presented.
    var presentedAt: Date?

    /// Frozen lesson title at time of presentation (for historical accuracy).
    var lessonTitleSnapshot: String?

    /// Frozen lesson subheading at time of presentation.
    var lessonSubheadingSnapshot: String?

    // MARK: - Planning Flags

    /// Whether students need more practice with this material.
    var needsPractice: Bool = false

    /// Whether this lesson should be presented again.
    var needsAnotherPresentation: Bool = false

    /// Description of follow-up work to assign.
    var followUpWork: String = ""

    /// General notes about this lesson assignment.
    var notes: String = ""

    // MARK: - CloudKit-Compatible Foreign Keys

    /// Lesson UUID stored as string for CloudKit compatibility.
    var lessonID: String = ""

    /// Student UUIDs stored as JSON-encoded data for CloudKit compatibility.
    @Attribute(.externalStorage) private var _studentIDsData: Data?

    /// Student IDs as string array. Uses JSON encoding for safe storage.
    @Transient
    var studentIDs: [String] {
        get {
            guard let data = _studentIDsData else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
        set {
            _studentIDsData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Denormalized key for grouping by student set. Automatically updated.
    var studentGroupKeyPersisted: String = ""

    // MARK: - Track Integration

    /// Track UUID if this lesson is part of a track.
    var trackID: String?

    /// TrackStep UUID if this lesson is a step in a track.
    var trackStepID: String?

    // MARK: - Migration Tracking

    /// ID of the StudentLesson this was migrated from (nil for new records).
    var migratedFromStudentLessonID: String?

    /// ID of the Presentation this was migrated from (nil for new records).
    var migratedFromPresentationID: String?

    // MARK: - Relationships

    /// Direct relationship to the lesson being assigned.
    @Relationship var lesson: Lesson?

    /// Notes attached to this lesson assignment.
    @Relationship(deleteRule: .cascade, inverse: \Note.lessonAssignment)
    var unifiedNotes: [Note]? = []

    /// Transient array for resolved Student objects.
    @Transient var students: [Student] = []

    // MARK: - Computed Properties

    /// Convenience accessor for lessonID as UUID.
    var lessonIDUUID: UUID? {
        get { UUID(uuidString: lessonID) }
        set { lessonID = newValue?.uuidString ?? "" }
    }

    /// Student IDs as UUIDs.
    var studentUUIDs: [UUID] {
        studentIDs.compactMap { UUID(uuidString: $0) }
    }

    /// Whether this assignment is in the draft state.
    var isDraft: Bool { state == .draft }

    /// Whether this assignment is scheduled.
    var isScheduled: Bool { state == .scheduled || scheduledFor != nil }

    /// Whether this assignment has been presented.
    var isPresented: Bool { state == .presented }

    // MARK: - Initializers

    /// Creates a new lesson assignment.
    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        state: LessonAssignmentState = .draft,
        scheduledFor: Date? = nil,
        presentedAt: Date? = nil,
        lessonID: UUID,
        studentIDs: [UUID] = [],
        lesson: Lesson? = nil,
        needsPractice: Bool = false,
        needsAnotherPresentation: Bool = false,
        followUpWork: String = "",
        notes: String = "",
        trackID: String? = nil,
        trackStepID: String? = nil
    ) {
        self.id = id
        self.createdAt = createdAt
        self.modifiedAt = createdAt
        self.stateRaw = state.rawValue
        self.scheduledFor = scheduledFor
        self.scheduledForDay = scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
        self.presentedAt = presentedAt
        self.lessonID = lessonID.uuidString
        self._studentIDsData = try? JSONEncoder().encode(studentIDs.map { $0.uuidString })
        self.lesson = lesson
        self.needsPractice = needsPractice
        self.needsAnotherPresentation = needsAnotherPresentation
        self.followUpWork = followUpWork
        self.notes = notes
        self.trackID = trackID
        self.trackStepID = trackStepID
        self.unifiedNotes = []

        updateDenormalizedKeys()
    }

    /// Creates a lesson assignment from a Lesson and Students.
    init(
        id: UUID = UUID(),
        lesson: Lesson,
        students: [Student] = [],
        state: LessonAssignmentState = .draft,
        scheduledFor: Date? = nil
    ) {
        self.id = id
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.stateRaw = state.rawValue
        self.scheduledFor = scheduledFor
        self.scheduledForDay = scheduledFor.map { AppCalendar.startOfDay($0) } ?? Date.distantPast
        self.lesson = lesson
        self.lessonID = lesson.id.uuidString
        self.students = students
        self._studentIDsData = try? JSONEncoder().encode(students.map { $0.id.uuidString })
        self.unifiedNotes = []

        updateDenormalizedKeys()
    }

    // MARK: - State Transitions

    /// Schedules this assignment for a specific date.
    func schedule(for date: Date, using calendar: Calendar = AppCalendar.shared) {
        self.scheduledFor = date
        self.scheduledForDay = calendar.startOfDay(for: date)
        self.state = .scheduled
        self.modifiedAt = Date()
    }

    /// Removes the scheduled date, returning to draft state.
    func unschedule() {
        self.scheduledFor = nil
        self.scheduledForDay = Date.distantPast
        self.state = .draft
        self.modifiedAt = Date()
    }

    /// Marks this assignment as presented.
    func markPresented(at date: Date = Date(), snapshotLesson: Bool = true) {
        self.presentedAt = date
        self.state = .presented
        self.modifiedAt = Date()

        if snapshotLesson, let lesson = self.lesson {
            self.lessonTitleSnapshot = lesson.name
            self.lessonSubheadingSnapshot = lesson.subheading
        }
    }

    // MARK: - Helpers

    /// Updates denormalized keys for efficient querying.
    func updateDenormalizedKeys() {
        let ids = studentUUIDs.sorted { $0.uuidString < $1.uuidString }
        self.studentGroupKeyPersisted = ids.map { $0.uuidString }.joined(separator: ",")
    }

    /// Syncs transient relationships from stored IDs.
    func syncSnapshotsFromRelationships() {
        self.lessonID = self.lesson?.id.uuidString ?? self.lessonID
        let stringIDs = self.students.map { $0.id.uuidString }
        self.studentIDs = stringIDs
        updateDenormalizedKeys()
    }

    /// Normalizes denormalized date fields.
    func normalizeDenormalizedFields() {
        if let s = scheduledFor {
            scheduledForDay = AppCalendar.startOfDay(s)
        } else {
            scheduledForDay = Date.distantPast
        }
    }
}

// MARK: - State Enum

/// Lifecycle states for a lesson assignment.
enum LessonAssignmentState: String, Codable, CaseIterable {
    /// Created but not yet scheduled.
    case draft = "draft"

    /// Has a scheduled date for presentation.
    case scheduled = "scheduled"

    /// Has been presented to students (historical record).
    case presented = "presented"
}

// MARK: - Debug Extensions

#if DEBUG
extension LessonAssignment {
    var debugDescription: String {
        let studentCount = studentIDs.count
        return "LessonAssignment(id=\(id), state=\(state.rawValue), lessonID=\(lessonID.prefix(8))..., students=\(studentCount))"
    }
}
#endif
