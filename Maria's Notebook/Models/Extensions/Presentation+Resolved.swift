//
//  Presentation+Resolved.swift
//  Maria's Notebook
//
//  Computed properties for resolving relationships and IDs.
//

import Foundation

// MARK: - DenormalizedSchedulable Conformance

extension Presentation: DenormalizedSchedulable {
    /// Prefer the relationship; fall back to stored IDs for compatibility.
    var resolvedStudentIDs: [UUID] {
        if !students.isEmpty { return students.map { $0.id } }
        return studentUUIDs
    }

    // Bridge properties for protocol default implementations
    var lessonRelationshipID: UUID? { lesson?.id }
    var studentRelationshipIDStrings: [String] { students.uuidStrings }
}

// MARK: - Display Helpers

extension Presentation {
    /// Display title - prefer snapshot for historical accuracy, fall back to lesson relationship.
    var displayTitle: String {
        lessonTitleSnapshot ?? lesson?.name ?? "Unknown Lesson"
    }

    /// Display subheading - prefer snapshot for historical accuracy, fall back to lesson relationship.
    var displaySubheading: String {
        lessonSubheadingSnapshot ?? lesson?.subheading ?? ""
    }

    /// Whether this presentation has any students assigned.
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

extension Presentation {
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

    /// Whether this presentation can be scheduled (is in draft state).
    var canSchedule: Bool {
        state == .draft
    }

    /// Whether this presentation can be marked as presented.
    var canPresent: Bool {
        state != .presented
    }

    /// Whether this presentation can be unscheduled (is in scheduled state).
    var canUnschedule: Bool {
        state == .scheduled
    }
}

// MARK: - Comparison with StudentLesson

extension Presentation {
    /// Check if this presentation was migrated from a specific StudentLesson.
    func wasMigratedFrom(studentLesson: StudentLesson) -> Bool {
        migratedFromStudentLessonID == studentLesson.id.uuidString
    }

    /// Check if this presentation was migrated from an old Presentation with the given ID.
    func wasMigratedFromOldPresentation(id: UUID) -> Bool {
        migratedFromPresentationID == id.uuidString
    }

    /// Check if this presentation matches a StudentLesson's key properties.
    func matches(studentLesson sl: StudentLesson) -> Bool {
        // Match by lesson and student set
        guard lessonID == sl.lessonID else { return false }
        return studentGroupKey == sl.studentGroupKey
    }
}

// MARK: - Track Integration

extension Presentation {
    /// Whether this presentation is part of a track.
    var isPartOfTrack: Bool {
        trackID.map { !$0.isEmpty } ?? false
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
