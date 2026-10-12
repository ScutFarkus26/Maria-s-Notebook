//
//  OpenLessonIntent.swift
//  Cosmic Daybook
//
//  Opens a lesson in the Lessons library (and powers tapping a lesson in
//  Spotlight search), through the router's own lesson link, which Lessons
//  picks up when it appears.
//

import AppIntents

struct OpenLessonIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Lesson"
    static let description = IntentDescription(
        "Open a lesson in Cosmic Daybook.",
        categoryName: "Navigation"
    )

    @Parameter(title: "Lesson")
    var target: LessonEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.navigateToLesson(target.id)
        return .result()
    }
}
