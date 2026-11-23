import SwiftUI
import CoreData
import Foundation

// NOTE: Renamed type: GiveLessonViewModel -> CDLessonPickerViewModel

// MARK: - View Model

/// The lesson picker's search text and selection (`LessonSection`). The
/// members the old Give Lesson sheet kept here (children, dates, notes, a
/// plan/given mode) were read by nothing and went on 2026-11-22.
@Observable
final class LessonPickerViewModel {
    // MARK: - Properties

    var selectedLessonID: UUID?
    var lessonSearchText: String = ""

    // MARK: - Private Properties

    /// Every lesson, in picker order.
    private var allLessons: [CDLesson] = []

    // MARK: - Initialization

    init(selectedLessonID: UUID? = nil) {
        self.selectedLessonID = selectedLessonID
    }

    // MARK: - Configuration

    func configure(lessons: [CDLesson]) {
        self.allLessons = Self.sortLessons(lessons)

        // If a lesson is already selected and the field is empty, show its name in the search field
        if lessonSearchText.trimmed().isEmpty,
           let id = selectedLessonID,
           let l = self.allLessons.first(where: { $0.id == id }) {
            lessonSearchText = l.name
        }
    }

    // MARK: - Computed Properties

    var filteredLessons: [CDLesson] {
        let query = lessonSearchText.normalizedForComparison()
        guard !query.isEmpty else { return allLessons }

        return allLessons.filter { lesson in
            lesson.name.lowercased().contains(query) ||
            lesson.area.lowercased().contains(query) ||
            lesson.sequence.lowercased().contains(query)
        }
    }

    // MARK: - Actions

    func selectLesson(_ lessonID: UUID) {
        selectedLessonID = lessonID
        if let l = allLessons.first(where: { $0.id == lessonID }) {
            lessonSearchText = l.name
        } else {
            lessonSearchText = ""
        }
    }

    // MARK: - Sorting

    private static func sortLessons(_ lessons: [CDLesson]) -> [CDLesson] {
        StringSorting.sortByMultipleLocalizedCaseInsensitive(
            items: lessons,
            keyPaths: [\.name, \.area, \.sequence],
            fallback: { ($0.id?.uuidString ?? "") < ($1.id?.uuidString ?? "") }
        )
    }

    // MARK: - Formatting Helpers

    func lessonDisplayTitle(for lesson: CDLesson) -> String {
        LessonFormatter.displayTitle(
            name: lesson.name,
            area: lesson.area,
            sequence: lesson.sequence
        )
    }
}
