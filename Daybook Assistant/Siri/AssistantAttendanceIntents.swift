import AppIntents
import CoreData

// The Assistant's own attendance commands, beside the shared here / late /
// absent / undo. Both read names aloud or change the whole class, so both
// need the phone unlocked.

// MARK: - Close arrival

/// The Close Arrival button by voice: everyone still unmarked is marked absent, and
/// from then on "Mark Maya here" marks late.
struct CloseArrivalIntent: AppIntent {
    static let title: LocalizedStringResource = "Close Arrival"
    static let description = IntentDescription(
        "Mark every unmarked child absent. A child who arrives after this is marked late.",
        categoryName: "Attendance"
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = try SiriAttendance()
        let check = try await SiriAttendance.plainly("checking arrival") {
            try AssistantSiriCommands.checkClose(session)
        }
        switch check {
        case .alreadyClosed:
            return .result(dialog: "Arrival is already closed.")
        case .notSchoolDay:
            return .result(dialog: "Today isn't a school day, so there's no arrival to close.")
        case .ready(let waiting):
            if waiting > 0 {
                try await requestConfirmation(
                    dialog: "Mark the \(waiting) unmarked \(waiting == 1 ? "child" : "children") absent?"
                )
            }
        }
        let count = try await SiriAttendance.plainly("closing arrival") {
            try await AssistantSiriCommands.closeArrival(session)
        }
        if count == 0 {
            return .result(dialog: "Arrival is closed. Everyone was already marked.")
        }
        return .result(dialog: IntentDialog(
            full: "Arrival is closed. \(count) \(count == 1 ? "child is" : "children are") marked absent.",
            supporting: "\(count) absent"
        ))
    }
}

// MARK: - Who's missing

/// "Who's not here yet?": the children still unmarked today, by the names the
/// grid shows.
struct WhoIsMissingIntent: AppIntent {
    static let title: LocalizedStringResource = "Who's Not Marked"
    static let description = IntentDescription(
        "Hear which children aren't marked yet today.",
        categoryName: "Attendance"
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = try SiriAttendance()
        let names = try await SiriAttendance.plainly("reading who's missing") {
            try AssistantSiriCommands.missingNames(session)
        }
        guard let missing = names else {
            return .result(dialog: "Today isn't a school day.")
        }
        guard !missing.isEmpty else {
            return .result(dialog: "Everyone is marked.")
        }
        let count = missing.count
        return .result(dialog: IntentDialog(
            full: "\(count) not marked yet: \(missing.formatted(.list(type: .and))).",
            supporting: "\(count) not marked"
        ))
    }
}
