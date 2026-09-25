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
