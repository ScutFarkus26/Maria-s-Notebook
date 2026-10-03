// AppIntents.swift
// App Intents exposed to Siri and the Shortcuts app.

import AppIntents
import SwiftUI

// MARK: - Open Today

struct OpenTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Today"
    /// Superseded by `OpenSectionIntent`; kept so saved shortcuts still run.
    static let isDiscoverable = false
    static let description = IntentDescription(
        "Open the Today view in Cosmic Daybook.",
        categoryName: "Navigation"
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.navigateTo(.today)
        return .result()
    }
}

// MARK: - Open Students

struct OpenStudentsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Students"
    /// Superseded by `OpenSectionIntent`; kept so saved shortcuts still run.
    static let isDiscoverable = false
    static let description = IntentDescription(
        "Open the Students view in Cosmic Daybook.",
        categoryName: "Navigation"
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.navigateTo(.students)
        return .result()
    }
}

// MARK: - Open Lessons

struct OpenLessonsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Lessons"
    /// Superseded by `OpenSectionIntent`; kept so saved shortcuts still run.
    static let isDiscoverable = false
    static let description = IntentDescription(
        "Open the Lessons view in Cosmic Daybook.",
        categoryName: "Navigation"
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.navigateTo(.lessons)
        return .result()
    }
}

// MARK: - Open Attendance

struct OpenAttendanceIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Attendance"
    /// Superseded by `OpenSectionIntent`; kept so saved shortcuts still run.
    static let isDiscoverable = false
    static let description = IntentDescription(
        "Open the Attendance view in Cosmic Daybook.",
        categoryName: "Navigation"
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.navigateTo(.attendance)
        return .result()
    }
}

// MARK: - New Lesson

struct NewLessonIntent: AppIntent {
    static let title: LocalizedStringResource = "Create New Lesson"
    static let description = IntentDescription(
        "Open the new-lesson form in Cosmic Daybook.",
        categoryName: "Create"
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.requestNewLesson()
        return .result()
    }
}

// MARK: - Open a Section

/// The notebook's main screens, as Siri names them.
enum NotebookSection: String, AppEnum {
    case today, students, lessons, attendance, restock

    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Section" }

    static var caseDisplayRepresentations: [NotebookSection: DisplayRepresentation] {
        [
            .today: "Today",
            .students: "Students",
            .lessons: "Lessons",
            .attendance: DisplayRepresentation(title: "Attendance", synonyms: ["Attendance", "the roll"]),
            .restock: DisplayRepresentation(title: "Restock", synonyms: ["Restock", "Supplies", "the office run"])
        ]
    }
}

/// One App Shortcut for the main screens (four of them once took four of the
/// ten an app may have: the attendance commands needed the room). Restock
/// joined as a section, not a shortcut: the notebook is at the cap.
struct OpenSectionIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Section"
    static let description = IntentDescription(
        "Open Today, Students, Lessons, Attendance or Restock in Cosmic Daybook.",
        categoryName: "Navigation"
    )
    static let supportedModes: IntentModes = .foreground

    @Parameter(title: "Section")
    var section: NotebookSection

    @MainActor
    func perform() async throws -> some IntentResult {
        switch section {
        case .today: AppRouter.shared.navigateTo(.today)
        case .students: AppRouter.shared.navigateTo(.students)
        case .lessons: AppRouter.shared.navigateTo(.lessons)
        case .attendance: AppRouter.shared.navigateTo(.attendance)
        case .restock: AppRouter.shared.navigateTo(.supplies)
        }
        return .result()
    }
}

// MARK: - App Shortcuts Provider

/// Exposes the app's intents to Siri and the Shortcuts app without user setup.
struct CosmicDaybookAppShortcuts: AppShortcutsProvider {
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
            shortTitle: "Undo Attendance",
            systemImageName: "arrow.uturn.backward"
        )
        AppShortcut(
            intent: OpenSectionIntent(),
            phrases: [
                "Open \(\.$section) in \(.applicationName)",
                "Show me \(\.$section) in \(.applicationName)",
                "Go to \(\.$section) in \(.applicationName)"
            ],
            shortTitle: "Open Section",
            systemImageName: "sidebar.left"
        )
        AppShortcut(
            intent: NewLessonIntent(),
            phrases: [
                "Create a new lesson in \(.applicationName)",
                "New lesson in \(.applicationName)"
            ],
            shortTitle: "New Lesson",
            systemImageName: "book.badge.plus"
        )
        AppShortcut(
            intent: LogObservationIntent(),
            phrases: [
                "Log an observation in \(.applicationName)",
                "Record an observation in \(.applicationName)",
                "Log an observation about \(\.$student) in \(.applicationName)",
                "Add an observation about \(\.$student) in \(.applicationName)"
            ],
            shortTitle: "Log Observation",
            systemImageName: "square.and.pencil"
        )
        AppShortcut(
            intent: OpenStudentIntent(),
            phrases: [
                "Open a student in \(.applicationName)",
                "Open \(\.$target) in \(.applicationName)",
                "Show me \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Student",
            systemImageName: "person.crop.circle"
        )
        AppShortcut(
            intent: MarkLessonPresentedIntent(),
            phrases: [
                "Mark a lesson presented in \(.applicationName)",
                "Mark \(\.$lesson) as presented in \(.applicationName)",
                "Record a presentation in \(.applicationName)"
            ],
            shortTitle: "Mark Presented",
            systemImageName: "checkmark.seal"
        )
        AppShortcut(
            intent: OpenLessonIntent(),
            phrases: [
                "Open \(\.$target) in \(.applicationName)"
            ],
            shortTitle: "Open Lesson",
            systemImageName: "book"
        )
    }
}
