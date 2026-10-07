import AppIntents
import CoreData

/// What Siri offers in Daybook Assistant with no setup. Phrases must name the
/// app; for a bare "Mark Maya here", make a personal shortcut with that name
/// in the Shortcuts app.
struct AssistantAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MarkHereIntent(),
            phrases: [
                "Mark a student here in \(.applicationName)",
                "Mark \(\.$student) here in \(.applicationName)",
                "Mark \(\.$student) present in \(.applicationName)",
                "\(\.$student) is here in \(.applicationName)"
            ],
            shortTitle: "Mark Here",
            systemImageName: "person.fill.checkmark"
        )
        AppShortcut(
            intent: MarkLateIntent(),
            phrases: [
                "Mark a student late in \(.applicationName)",
                "Mark \(\.$student) late in \(.applicationName)",
                "Mark \(\.$student) tardy in \(.applicationName)",
                "\(\.$student) is late in \(.applicationName)"
            ],
            shortTitle: "Mark Late",
            systemImageName: "clock.badge.exclamationmark"
        )
        AppShortcut(
            intent: MarkAbsentIntent(),
            phrases: [
                "Mark a student absent in \(.applicationName)",
                "Mark \(\.$student) absent in \(.applicationName)",
                "\(\.$student) is absent in \(.applicationName)"
            ],
            shortTitle: "Mark Absent",
            systemImageName: "person.fill.xmark"
        )
        AppShortcut(
            intent: UndoAttendanceIntent(),
            phrases: [
                "Undo attendance in \(.applicationName)",
                "Undo my last attendance mark in \(.applicationName)"
            ],
            shortTitle: "Undo",
            systemImageName: "arrow.uturn.backward"
        )
        AppShortcut(
            intent: CloseArrivalIntent(),
            phrases: [
                "Close arrival in \(.applicationName)",
                "Start late arrivals in \(.applicationName)"
            ],
            shortTitle: "Close Arrival",
            systemImageName: "door.left.hand.closed"
        )
        AppShortcut(
            intent: WhoIsMissingIntent(),
            phrases: [
                "Who's not here yet in \(.applicationName)",
                "Who isn't marked in \(.applicationName)"
            ],
            shortTitle: "Who's Not Marked",
            systemImageName: "person.crop.circle.badge.questionmark"
        )
        AppShortcut(
            intent: WhoIsAbsentIntent(),
            phrases: [
                "Who's absent in \(.applicationName)",
                "Who's absent today in \(.applicationName)",
                "Who is absent in \(.applicationName)"
            ],
            shortTitle: "Who's Absent",
            systemImageName: "person.crop.circle.badge.xmark"
        )
        // All ten of Apple's ten: adding another means merging two.
        // Restock: the supply names come from
        // `SupplyEntityQuery.suggestedEntities()`.
        AppShortcut(
            intent: MarkSupplyOutIntent(),
            phrases: [
                "We're out of \(\.$supply) in \(.applicationName)",
                "We ran out of \(\.$supply) in \(.applicationName)",
                "Mark a supply out in \(.applicationName)"
            ],
            shortTitle: "We're Out",
            systemImageName: "battery.0"
        )
        AppShortcut(
            intent: MarkSupplyLowIntent(),
            phrases: [
                "We're low on \(\.$supply) in \(.applicationName)",
                "We're running low on \(\.$supply) in \(.applicationName)",
                "Mark a supply low in \(.applicationName)"
            ],
            shortTitle: "We're Low",
            systemImageName: "battery.25"
        )
        AppShortcut(
            intent: AddToOfficeRunIntent(),
            phrases: [
                "Add to the office run in \(.applicationName)",
                "Add something to the office run in \(.applicationName)",
                "We need something from the office in \(.applicationName)"
            ],
            shortTitle: "Add to Office Run",
            systemImageName: "building.2"
        )
    }
}

/// Keeps Siri's list of names in step with the class. The names come from
/// `StudentEntityQuery.suggestedEntities()`; this only tells the system to
/// read them again, and only when the roster has changed since it last did.
@MainActor
enum AssistantSiriVocabulary {
    private static var registered: [String]?

    static func refresh(for students: [CDStudent]) {
        let names = students.map { "\($0.id?.uuidString ?? "")|\($0.firstName)|\($0.lastName)|\($0.nickname ?? "")" }
        guard names != registered else { return }
        registered = names
        AssistantAppShortcuts.updateAppShortcutParameters()
    }
}

/// Keeps Siri's supply names in step with the shelf, as
/// `AssistantSiriVocabulary` does with the class: the names come from
/// `SupplyEntityQuery.suggestedEntities()`, and this tells the system to read
/// them again only when the staples have changed since it last did.
@MainActor
enum AssistantRestockVocabulary {
    private static var registered: [String]?

    static func refresh(for staples: [CDSupply]) {
        let names = staples.map { "\($0.id?.uuidString ?? "")|\($0.name)" }
        guard names != registered else { return }
        registered = names
        AssistantAppShortcuts.updateAppShortcutParameters()
    }
}
