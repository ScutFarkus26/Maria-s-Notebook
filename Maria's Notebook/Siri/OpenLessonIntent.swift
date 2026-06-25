//
//  OpenLessonIntent.swift
//  Maria's Notebook
//
//  Opens the Lessons library (and powers tapping a lesson in Spotlight search).
//  Per-lesson deep-linking isn't wired in the router yet, so this lands on the
//  Lessons list — still the right destination for "open lessons".
//

import AppIntents

struct OpenLessonIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Lesson"
    static let description = IntentDescription(
        "Open a lesson in Maria's Notebook.",
        categoryName: "Navigation"
    )

    @Parameter(title: "Lesson")
    var target: LessonEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.navigateTo(.lessons)
        return .result()
    }
}
