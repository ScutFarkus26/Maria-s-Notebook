import Foundation

// MARK: - Legacy WorkType (Deprecated)

/// Legacy work type enum preserved for backward compatibility during migration.
/// New code should use WorkKind instead.
///
/// This enum was previously nested inside the SwiftData WorkModel class.
/// It is now top-level so that references like WorkModel.WorkType continue
/// to resolve via the CDWorkModel typealias.
@available(*, deprecated, message: "Use WorkKind instead. LegacyWorkType is maintained for backwards compatibility only.")
enum LegacyWorkType: String, CaseIterable, Codable, Sendable {
    case research = "Research"
    case followUp = "Follow Up"
    case practice = "Practice"
    case report = "Report"
}
