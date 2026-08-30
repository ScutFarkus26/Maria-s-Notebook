//
//  OpenStudentIntent.swift
//  Maria's Notebook
//
//  Opens a student's profile. Powers "Open Maria in Montessori Daybook" and the
//  tap action on a student that appears in Spotlight search results.
//

import AppIntents

struct OpenStudentIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Student"
    static let description = IntentDescription(
        "Open a student's profile in Montessori Daybook.",
        categoryName: "Navigation"
    )

    @Parameter(title: "Student")
    var target: StudentEntity

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.requestOpenStudentDetail(target.id)
        return .result()
    }
}
