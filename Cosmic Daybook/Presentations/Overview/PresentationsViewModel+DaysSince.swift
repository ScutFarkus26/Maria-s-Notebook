// PresentationsViewModel+DaysSince.swift

import Foundation

// MARK: - Days Since Last CDLesson

extension PresentationsViewModel {
    /// Each student's wait since her last given lesson, by the one rule
    /// (`DaysSinceLastLesson`): Parsha lessons aside, undated marks skipped,
    /// in school days. `Int.max` for a child never given one; also the area of
    /// her last lesson.
    func calculateDaysSinceLastLesson(
        lessonAssignments: [CDLessonAssignment],
        lessons: [CDLesson],
        students: [CDStudent]
    ) {
        let parshaLessonIDs = Set(
            lessons.filter { DaysSinceLastLesson.isParsha(area: $0.area, sequence: $0.sequence) }.compactMap(\.id)
        )
        let given = lessonAssignments.filter(\.isGiven).map {
            DaysSinceLastLesson.Given(
                lessonID: $0.resolvedLessonID,
                studentIDs: $0.resolvedStudentIDs,
                date: DaysSinceLastLesson.givenDate(presentedAt: $0.presentedAt, scheduledFor: $0.scheduledFor)
            )
        }
        let lastLessons = DaysSinceLastLesson.lastLessons(from: given, parshaLessonIDs: parshaLessonIDs)

        // Sync can hand back two rows with one id; keep the first.
        let lessonsByID: [UUID: CDLesson] = Dictionary(
            lessons.compactMap { lesson in
                guard let id = lesson.id else { return nil }
                return (id, lesson)
            },
            uniquingKeysWith: { first, _ in first }
        )

        var result: [UUID: Int] = [:]
        var areas: [UUID: String] = [:]
        let now = Date()
        for s in students {
            guard let sid = s.id else { continue }
            if let last = lastLessons[sid] {
                guard let viewContext else { continue }
                result[sid] = DaysSinceLastLesson.schoolDays(since: last.date, asOf: now, using: viewContext)
            } else {
                result[sid] = Int.max
            }
            if let lessonID = lastLessons[sid]?.lessonID,
               let area = lessonsByID[lessonID]?.area,
               !area.isEmpty {
                areas[sid] = area
            }
        }

        self.daysSinceLastLessonByStudent = result
        self.lastAreaByStudent = areas
    }
}
