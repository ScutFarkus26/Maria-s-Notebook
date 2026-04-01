//
//  Presentation+Resolved.swift
//  Maria's Notebook
//
//  Computed properties for resolving relationships and IDs.
//

import Foundation

// MARK: - DenormalizedSchedulable Conformance

extension Presentation: DenormalizedSchedulable {
    /// Resolved student IDs from stored string IDs.
    var resolvedStudentIDs: [UUID] {
        studentUUIDs
    }

    // Bridge properties for protocol default implementations
    var lessonRelationshipID: UUID? { lesson?.id }
    var studentRelationshipIDStrings: [String] { studentIDs }
}

// MARK: - Display Helpers

extension Presentation {
    /// Display title - prefer snapshot for historical accuracy, fall back to lesson relationship.
    var displayTitle: String {
        lessonTitleSnapshot ?? lesson?.name ?? "Unknown CDLesson"
    }

    /// Display subheading - prefer snapshot for historical accuracy, fall back to lesson relationship.
    var displaySubheading: String {
        lessonSubheadingSnapshot ?? lesson?.subheading ?? ""
    }

    /// Whether this presentation has any students assigned.
    var hasStudents: Bool {
        !studentIDs.isEmpty
    }

    /// Number of students assigned.
    var studentCount: Int {
        studentIDs.count
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

// MARK: - Migration Helpers

extension Presentation {
    /// Check if this presentation was migrated from an old Presentation with the given ID.
    func wasMigratedFromOldPresentation(id: UUID) -> Bool {
        migratedFromPresentationID == id.uuidString
    }
}

// MARK: - CDTrackEntity Integration

extension Presentation {
    /// Whether this presentation is part of a track.
    var isPartOfTrack: Bool {
        trackID.map { !$0.isEmpty } ?? false
    }

    /// CDTrackEntity ID as UUID, if valid.
    var trackIDUUID: UUID? {
        trackID.flatMap { UUID(uuidString: $0) }
    }

    /// CDTrackEntity step ID as UUID, if valid.
    var trackStepIDUUID: UUID? {
        trackStepID.flatMap { UUID(uuidString: $0) }
    }
}
