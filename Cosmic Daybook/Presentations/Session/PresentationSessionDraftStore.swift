import Foundation

/// The decisions a guide chose and left with Later, kept per presentation
/// until Done applies them.
///
/// Notes are not here: Later saves them to the notebook straight away (they are
/// facts), and only the plans wait. One small JSON blob per presentation,
/// removed on Done.
nonisolated enum PresentationSessionDraftStore {
    struct Draft: Codable, Equatable, Sendable {
        var everyone: String
        var overrides: [String: String]
        var checkInDay: Date?
        var savedAt: Date
    }

    static func key(for presentationID: UUID) -> String {
        "PresentationSession.draft.\(presentationID.uuidString)"
    }

    static func load(
        presentationID: UUID,
        defaults: UserDefaults = .standard
    ) -> Draft? {
        guard let data = defaults.data(forKey: key(for: presentationID)) else { return nil }
        return try? JSONDecoder().decode(Draft.self, from: data)
    }

    static func save(
        _ draft: Draft,
        presentationID: UUID,
        defaults: UserDefaults = .standard
    ) {
        guard let data = try? JSONEncoder().encode(draft) else { return }
        defaults.set(data, forKey: key(for: presentationID))
    }

    static func clear(
        presentationID: UUID,
        defaults: UserDefaults = .standard
    ) {
        defaults.removeObject(forKey: key(for: presentationID))
    }
}
