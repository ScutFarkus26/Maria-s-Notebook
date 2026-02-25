import Foundation

// MARK: - Unified Observation Item

/// Unified note item for displaying all note types in ObservationsView.
struct UnifiedObservationItem: Identifiable {
    let id: UUID
    let date: Date
    let body: String
    let tags: [String]
    let includeInReport: Bool
    let imagePath: String?
    let contextText: String?
    let studentIDs: [UUID]

    // Source tracking for editing
    enum Source {
        case note(Note)
    }
    let source: Source
}
