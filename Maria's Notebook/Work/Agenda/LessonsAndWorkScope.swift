import Foundation

/// The guide-facing lenses inside the shared Lessons & Work workspace.
///
/// These are intentionally named for what is happening next, rather than for
/// the Core Data record type that happens to power each pane.
enum LessonsAndWorkScope: String, CaseIterable, Identifiable, Sendable {
    case needsAttention
    case upcoming
    case childrenWorking
    case history

    var id: Self { self }

    var title: String {
        switch self {
        case .needsAttention: "Needs Attention"
        case .upcoming: "Upcoming"
        case .childrenWorking: "Children Working"
        case .history: "History"
        }
    }

    var compactTitle: String {
        switch self {
        case .needsAttention: "Attention"
        case .upcoming: "Upcoming"
        case .childrenWorking: "Working"
        case .history: "History"
        }
    }

    var systemImage: String {
        switch self {
        case .needsAttention: "eye.circle"
        case .upcoming: "calendar"
        case .childrenWorking: "tray.full"
        case .history: "clock.arrow.circlepath"
        }
    }

    static func resolved(rawValue: String?) -> Self {
        guard let rawValue, let scope = Self(rawValue: rawValue) else {
            return .needsAttention
        }
        return scope
    }

    /// Returns the most useful place to continue after the guide closes the
    /// post-presentation reflection. An unresolved guide responsibility comes
    /// first, followed by named child work, then the completed record.
    static func afterPresentation(
        hasOpenFollowUp: Bool,
        hasOpenWork: Bool
    ) -> Self {
        if hasOpenFollowUp { return .needsAttention }
        if hasOpenWork { return .childrenWorking }
        return .history
    }
}
