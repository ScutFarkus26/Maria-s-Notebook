import Foundation

/// A stable pointer back to a classroom record used by an AI-assisted feature.
enum EvidenceEntityKind: String, Codable, Sendable {
    case note
    case presentation
    case work
    case lesson
    case student
    case todo
}

nonisolated struct EvidenceReference: Identifiable, Codable, Hashable, Sendable {
    let entityKind: EvidenceEntityKind
    let entityID: UUID
    let date: Date?
    let title: String
    let excerpt: String

    var id: String { "\(entityKind.rawValue)-\(entityID.uuidString)" }
}

/// Describes how much relevant evidence is available. It is deliberately not a
/// judgment of a child's readiness or ability.
enum EvidenceCompleteness: String, Codable, CaseIterable, Sendable {
    case strong = "Strong evidence"
    case some = "Some evidence"
    case insufficient = "More observation needed"
}

struct GroundedAIResponse: Codable, Sendable {
    let text: String
    let sources: [EvidenceReference]
}
