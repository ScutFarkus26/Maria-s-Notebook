import Foundation

/// A set of filters used to control the display of works in the UI.
struct WorkFilters: Equatable, Codable {
    /// Text to filter works by search terms.
    var search: String = ""
    /// Whether to show works marked as practice.
    var showPractice: Bool = true
    /// Whether to show works marked as follow-up.
    var showFollowUp: Bool = true
    /// Whether to show works marked as research.
    var showResearch: Bool = true
    /// Filter works by their status.
    var status: Status = .open

    /// The status of works to filter.
    enum Status: String, CaseIterable, Codable {
        case open
        case closed
        case all
    }

    /// The default set of filters.
    static let `default` = WorkFilters()
}
