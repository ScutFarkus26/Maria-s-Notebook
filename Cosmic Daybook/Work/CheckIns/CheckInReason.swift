import Foundation

/// Reason for scheduling a work check-in.
enum CheckInReason: String, Codable, CaseIterable, Identifiable, Sendable {
    case progressCheck
    case dueDate
    case assessment
    case followUp
    case studentRequest
    case other

    var id: String { rawValue }

    /// Maps to a human-readable purpose string for the WorkCheckIn entity.
    var purpose: String {
        switch self {
        case .progressCheck: return "Progress Check"
        case .dueDate: return "Due Date"
        case .assessment: return "Assessment"
        case .followUp: return "Follow Up"
        case .studentRequest: return "Student Request"
        case .other: return "Other"
        }
    }

    /// How a stored `CDWorkCheckIn.purpose` reads on screen.
    ///
    /// The column holds two spellings of the same purposes, and both are live.
    /// The Quick New Work sheet writes the title ("Progress Check"), while the
    /// calendar's drop prompt, the work detail's planner, the agenda's bulk
    /// check and Today's follow-up write the raw case name ("progressCheck").
    /// Rewriting either side would leave the rows already synced in the other
    /// spelling, and the raw names are also what the drop prompt's picker tags
    /// match on, so the stored text is left alone and every place that shows
    /// it goes through here instead.
    ///
    /// A raw name or a title, in any case, comes back as the title; anything
    /// else (a purpose typed over MCP, "Review Golden Beads") is returned as
    /// written, trimmed.
    static func displayName(forStoredPurpose stored: String) -> String {
        let trimmed = stored.trimmed()
        guard !trimmed.isEmpty else { return "" }
        let match = allCases.first { reason in
            reason.rawValue.caseInsensitiveCompare(trimmed) == .orderedSame
                || reason.purpose.caseInsensitiveCompare(trimmed) == .orderedSame
        }
        return match?.purpose ?? trimmed
    }

    /// The symbol a check-in pill draws beside a stored purpose. Read off the
    /// words rather than the case, so the raw names, the titles and a purpose
    /// typed by hand all land on the same icon. Both pills used to carry their
    /// own copy of this.
    static func iconName(forStoredPurpose stored: String) -> String {
        let purpose = stored.lowercased()
        if purpose.contains("progress") || purpose.contains("check") {
            return "checkmark.circle"
        } else if purpose.contains("due") {
            return "calendar.badge.exclamationmark"
        } else if purpose.contains("assessment") {
            return "chart.bar"
        } else if purpose.contains("follow") {
            return "arrow.turn.down.right"
        } else {
            return "calendar"
        }
    }
}
