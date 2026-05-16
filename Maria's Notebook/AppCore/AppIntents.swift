// AppIntents.swift
// App Intents exposed to Siri and the Shortcuts app.

import AppIntents
import SwiftUI

// MARK: - Open Today

struct OpenTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Today"
    static let description = IntentDescription(
        "Open the Today view in Maria's Notebook.",
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
    static let description = IntentDescription(
        "Open the Students view in Maria's Notebook.",
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
    static let description = IntentDescription(
        "Open the Lessons view in Maria's Notebook.",
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
    static let description = IntentDescription(
        "Open the Attendance view in Maria's Notebook.",
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
        "Open the new-lesson form in Maria's Notebook.",
        categoryName: "Create"
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.requestNewLesson()
        return .result()
    }
}

// MARK: - App Shortcuts Provider

/// Exposes the app's intents to Siri and the Shortcuts app without user setup.
struct MariasNotebookAppShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenTodayIntent(),
            phrases: [
                "Open Today in \(.applicationName)",
                "Show me Today in \(.applicationName)",
                "What's on Today in \(.applicationName)"
            ],
            shortTitle: "Open Today",
            systemImageName: "sun.max"
        )
        AppShortcut(
            intent: OpenStudentsIntent(),
            phrases: [
                "Open Students in \(.applicationName)",
                "Show me Students in \(.applicationName)"
            ],
            shortTitle: "Open Students",
            systemImageName: "person.2"
        )
        AppShortcut(
            intent: OpenLessonsIntent(),
            phrases: [
                "Open Lessons in \(.applicationName)",
                "Show me Lessons in \(.applicationName)"
            ],
            shortTitle: "Open Lessons",
            systemImageName: "book"
        )
        AppShortcut(
            intent: OpenAttendanceIntent(),
            phrases: [
                "Open Attendance in \(.applicationName)",
                "Take attendance in \(.applicationName)"
            ],
            shortTitle: "Open Attendance",
            systemImageName: "checkmark.circle"
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
    }
}
