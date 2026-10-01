import Foundation

/// Names for a meeting's work and lessons, falling back to the catalog when a
/// row carries only a lesson id.
struct MeetingCatalogNames {
    let catalog: LessonCatalog

    func lesson(for assignment: CDLessonAssignment) -> CDLesson? {
        assignment.lesson ?? assignment.lessonIDUUID.flatMap { catalog.lesson(id: $0) }
    }

    func lessonName(_ assignment: CDLessonAssignment) -> String {
        lesson(for: assignment)?.name ?? assignment.lessonTitleSnapshot ?? "Lesson"
    }

    func workTitle(_ work: CDWorkModel) -> String {
        let title = work.title.trimmed()
        if !title.isEmpty { return title }
        return UUID(uuidString: work.lessonID).flatMap { catalog.lesson(id: $0)?.name } ?? "Work"
    }
}
