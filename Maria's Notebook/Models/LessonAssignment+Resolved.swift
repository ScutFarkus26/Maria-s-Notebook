//
//  LessonAssignment+Resolved.swift
//  Maria's Notebook
//
//  Computed properties for resolving relationships and IDs.
//  Mirrors StudentLesson+Resolved for API compatibility.
//

import Foundation

extension LessonAssignment {
    /// Prefer the relationship's ID; fall back to stored ID for compatibility.
    var resolvedLessonID: UUID {
        lesson?.id ?? (UUID(uuidString: lessonID) ?? UUID())
    }

    /// Prefer the relationship; fall back to stored IDs for compatibility.
    var resolvedStudentIDs: [UUID] {
        if !students.isEmpty { return students.map { $0.id } }
        return studentUUIDs
    }

    /// Order-insensitive key for quick equality/group checks.
    var studentGroupKey: String {
        if !studentGroupKeyPersisted.isEmpty { return studentGroupKeyPersisted }
        let ids = resolvedStudentIDs.sorted { $0.uuidString < $1.uuidString }
        return ids.map { $0.uuidString }.joined(separator: ",")
    }

    /// Display title - prefer snapshot for historical accuracy, fall back to lesson relationship.
    var displayTitle: String {
        lessonTitleSnapshot ?? lesson?.name ?? "Unknown Lesson"
    }

    /// Display subheading - prefer snapshot for historical accuracy, fall back to lesson relationship.
    var displaySubheading: String {
        lessonSubheadingSnapshot ?? lesson?.subheading ?? ""
    }

    /// Whether this assignment has any students assigned.
    var hasStudents: Bool {
        !students.isEmpty || !studentIDs.isEmpty
    }

    /// Number of students assigned.
    var studentCount: Int {
        if !students.isEmpty { return students.count }
        return studentIDs.count
    }
}

// MARK: - State Helpers

extension LessonAssignment {
    /// Human-readable state description.
    var stateDescription: String {
        switch state {
        case .draft:
            return "Draft"
        case .scheduled:
            if let date = scheduledFor {
                return "Scheduled for \(date.formatted(date: .abbreviated, time: .omitted))"
            }
            return "Scheduled"
        case .presented:
            if let date = presentedAt {
                return "Presented on \(date.formatted(date: .abbreviated, time: .omitted))"
            }
            return "Presented"
        }
    }

    /// Whether this assignment can be scheduled (is in draft state).
    var canSchedule: Bool {
        state == .draft
    }

    /// Whether this assignment can be marked as presented.
    var canPresent: Bool {
        state != .presented
    }

    /// Whether this assignment can be unscheduled (is in scheduled state).
    var canUnschedule: Bool {
        state == .scheduled
    }
}

// MARK: - Comparison with StudentLesson

extension LessonAssignment {
    /// Check if this assignment was migrated from a specific StudentLesson.
    func wasMigratedFrom(studentLesson: StudentLesson) -> Bool {
        migratedFromStudentLessonID == studentLesson.id.uuidString
    }

    /// Check if this assignment was migrated from a specific Presentation.
    func wasMigratedFrom(presentation: Presentation) -> Bool {
        migratedFromPresentationID == presentation.id.uuidString
    }

    /// Check if this assignment matches a StudentLesson's key properties.
    func matches(studentLesson sl: StudentLesson) -> Bool {
        // Match by lesson and student set
        guard lessonID == sl.lessonID else { return false }
        return studentGroupKey == sl.studentGroupKey
    }
}

// MARK: - Track Integration

extension LessonAssignment {
    /// Whether this assignment is part of a track.
    var isPartOfTrack: Bool {
        trackID != nil && !trackID!.isEmpty
    }

    /// Track ID as UUID, if valid.
    var trackIDUUID: UUID? {
        trackID.flatMap { UUID(uuidString: $0) }
    }

    /// Track step ID as UUID, if valid.
    var trackStepIDUUID: UUID? {
        trackStepID.flatMap { UUID(uuidString: $0) }
    }
}
