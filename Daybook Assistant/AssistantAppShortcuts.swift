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
                "Undo my last Siri attendance mark in \(.applicationName)"
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
