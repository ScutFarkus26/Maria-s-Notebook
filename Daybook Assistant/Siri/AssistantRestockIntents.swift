import AppIntents

// Restock by voice: "We're out of paper towels", "We're low on tissues", and
// "Add to the office run". Each goes through `AssistantSiriRestock`, the
// shelf's own `RestockService` path. Saying a supply is low or out tells
// nobody nearby anything private, so all three work on a locked phone, as
// marking a child here does.

// MARK: - Out

struct MarkSupplyOutIntent: AppIntent {
    static let title: LocalizedStringResource = "We're Out"
    static let description = IntentDescription(
        "Mark a supply out. It goes on the office run, or your guide's order list if it's ordered.",
        categoryName: "Restock"
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Supply")
    var supply: SupplyAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("We're out of \(\.$supply)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let siri = try AssistantSiriRestock()
        return .result(dialog: try siri.mark(supply.id, as: .out).dialog(guideName: siri.guideName))
    }
}

// MARK: - Low

struct MarkSupplyLowIntent: AppIntent {
    static let title: LocalizedStringResource = "We're Low"
    static let description = IntentDescription(
        "Mark a supply as running low. It goes on the office run, or your guide's order list if it's ordered.",
        categoryName: "Restock"
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Supply")
    var supply: SupplyAppEntity

    static var parameterSummary: some ParameterSummary {
        Summary("We're low on \(\.$supply)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let siri = try AssistantSiriRestock()
        return .result(dialog: try siri.mark(supply.id, as: .low).dialog(guideName: siri.guideName))
    }
}

// MARK: - Office run

/// Anything at all, so it takes what she says rather than a name from the
/// shelf: an App Shortcut phrase can only carry a name Siri already knows,
/// so Siri asks "What do we need from the office?" A staple's name marks the
/// staple low instead of adding it twice; words in several staples' names
/// ("paper") are added as said, rather than marking one of them at a guess.
struct AddToOfficeRunIntent: AppIntent {
    static let title: LocalizedStringResource = "Add to Office Run"
    static let description = IntentDescription(
        "Add something to the next trip to the office.",
        categoryName: "Restock"
    )
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed

    @Parameter(title: "Item", requestValueDialog: "What do we need from the office?")
    var item: String

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$item) to the office run")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let siri = try AssistantSiriRestock()
        return .result(dialog: try siri.addToOfficeRun(item).dialog(guideName: siri.guideName))
    }
}
