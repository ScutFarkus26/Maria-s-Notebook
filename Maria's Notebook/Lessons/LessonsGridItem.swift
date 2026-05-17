// LessonsGridItem.swift
// Maria's Notebook
//
// Unified enum for representing both lessons and introductions in the lessons grid.

import Foundation

/// Represents either a lesson or an introduction in the lessons grid.
/// Introductions always sort before lessons within a sequence.
enum LessonsGridItem: Identifiable, Equatable {
    case introduction(CurriculumIntroduction)
    case lesson(CDLesson)

    var id: String {
        switch self {
        case .introduction(let intro):
            return "intro-\(intro.id.uuidString)"
        case .lesson(let lesson):
            return "lesson-\(lesson.id?.uuidString ?? UUID().uuidString)"
        }
    }

    /// Sort key to ensure introductions appear before lessons.
    /// 0 = introduction, 1 = lesson
    var sortKey: Int {
        switch self {
        case .introduction: return 0
        case .lesson: return 1
        }
    }

    /// The area associated with this item.
    var area: String {
        switch self {
        case .introduction(let intro):
            return intro.area
        case .lesson(let lesson):
            return lesson.area
        }
    }

    /// The sequence associated with this item.
    var sequence: String {
        switch self {
        case .introduction(let intro):
            return intro.sequence ?? ""
        case .lesson(let lesson):
            return lesson.sequence
        }
    }

    /// Whether this is an introduction item.
    var isIntroduction: Bool {
        if case .introduction = self { return true }
        return false
    }

    /// Whether this is a lesson item.
    var isLesson: Bool {
        if case .lesson = self { return true }
        return false
    }

    /// Extracts the lesson if this is a lesson item.
    var asLesson: CDLesson? {
        if case .lesson(let lesson) = self { return lesson }
        return nil
    }

    /// Extracts the introduction if this is an introduction item.
    var asIntroduction: CurriculumIntroduction? {
        if case .introduction(let intro) = self { return intro }
        return nil
    }

    // MARK: - Equatable

    static func == (lhs: LessonsGridItem, rhs: LessonsGridItem) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Collection Helpers

extension Array where Element == LessonsGridItem {
    /// Filters to only lesson items.
    var lessons: [CDLesson] {
        compactMap { $0.asLesson }
    }

    /// Filters to only introduction items.
    var introductions: [CurriculumIntroduction] {
        compactMap { $0.asIntroduction }
    }

    /// Sorts items so introductions come before lessons.
    func sortedWithIntroductionsFirst() -> [LessonsGridItem] {
        sorted { $0.sortKey < $1.sortKey }
    }
}
