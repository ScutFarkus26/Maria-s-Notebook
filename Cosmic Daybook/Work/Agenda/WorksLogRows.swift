// WorksLogRows.swift
// What the Works log shows for a row and which rows its filters keep, apart
// from the view so the rules can be tested.

import CoreData
import Foundation

enum WorksLogRows {

    /// The lesson a row was for: the lesson of the presentation it follows,
    /// else its own lesson from the catalog. Quick New Work's rows follow no
    /// presentation, so without the catalog they had no lesson at all.
    static func lesson(
        of work: CDWorkModel, linkedLesson: CDLesson?, lessonsByID: [UUID: CDLesson]
    ) -> CDLesson? {
        linkedLesson ?? UUID(uuidString: work.lessonID).flatMap { lessonsByID[$0] }
    }

    /// The row's own title, or its kind and the lesson it was for ("Practice:
    /// Checkerboard"), which the search also matches.
    ///
    /// - Parameters:
    ///   - linkedLesson: the lesson of the presentation the row follows.
    ///   - lessonsByID: the lesson catalog.
    static func title(
        of work: CDWorkModel, linkedLesson: CDLesson?, lessonsByID: [UUID: CDLesson]
    ) -> String {
        let title = work.title.trimmed()
        if !title.isEmpty { return title }
        let kindLabel = work.displayKind.shortLabel
        if let lesson = lesson(of: work, linkedLesson: linkedLesson, lessonsByID: lessonsByID) {
            return "\(kindLabel): \(lesson.name)"
        }
        return kindLabel
    }

    /// Whether the row passes the type filter (nil keeps every row). Untagged
    /// work is Practice, as the card says.
    static func matches(_ work: CDWorkModel, kind: WorkKind?) -> Bool {
        guard let kind else { return true }
        return work.displayKind == kind
    }

    /// Whether the row belongs to any of the children the filter picked
    /// (none picked keeps every row): her own copy of linked work, or a
    /// shared row she is on — never a classmate's copy that names her.
    static func matches(_ work: CDWorkModel, students: Set<UUID>, visibility: WorkVisibility) -> Bool {
        guard !students.isEmpty else { return true }
        return students.contains { visibility.isVisible(work, to: $0) }
    }
}
