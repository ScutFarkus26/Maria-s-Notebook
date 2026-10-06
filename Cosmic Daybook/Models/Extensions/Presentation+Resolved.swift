//
//  Presentation+Resolved.swift
//  Cosmic Daybook
//
//  Computed properties for resolving relationships and IDs.
//

import Foundation

// MARK: - DenormalizedSchedulable Conformance

extension Presentation: DenormalizedSchedulable {
    /// Resolved student IDs from stored string IDs.
    ///
    /// `nonisolated` so background contexts (e.g. `snapshot()`) can read it.
    nonisolated var resolvedStudentIDs: [UUID] {
        studentIDs.compactMap { UUID(uuidString: $0) }
    }

    // Bridge properties for protocol default implementations
    var lessonRelationshipID: UUID? { lesson?.id }
    var studentRelationshipIDStrings: [String] { studentIDs }

    /// The presentation's own id: stable, and no lesson's. (A row with no id
    /// either falls back to one fixed stand-in.)
    var placeholderLessonID: UUID { id ?? Self.lessonlessStandIn }

    private static let lessonlessStandIn = UUID(uuidString: "00000000-0000-0000-0000-00000000000F")!
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

}
