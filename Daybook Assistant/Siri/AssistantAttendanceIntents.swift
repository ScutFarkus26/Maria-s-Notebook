import AppIntents
import CoreData

// The Assistant's own attendance commands, beside the shared here / late /
// absent / undo. Each reads names aloud or changes the whole class, so each
// needs the phone unlocked.

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
        let session = try await SiriAttendance()
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
        let session = try await SiriAttendance()
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

// MARK: - Who's absent

/// "Who's absent?": the children marked absent today, by the names the grid
/// shows.
struct WhoIsAbsentIntent: AppIntent {
    static let title: LocalizedStringResource = "Who's Absent"
    static let description = IntentDescription(
        "Hear which children are marked absent today.",
        categoryName: "Attendance"
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let session = try await SiriAttendance()
        let names = try await SiriAttendance.plainly("reading who's absent") {
            try AssistantSiriCommands.absentNames(session)
        }
        guard let absent = names else {
            return .result(dialog: "Today isn't a school day.")
        }
        guard !absent.isEmpty else {
            return .result(dialog: "No one is marked absent.")
        }
        let count = absent.count
        return .result(dialog: IntentDialog(
            full: "\(count) absent: \(absent.formatted(.list(type: .and))).",
            supporting: "\(count) absent"
        ))
    }
}
