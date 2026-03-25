// PresentationsViewModel+DaysSince.swift

import Foundation
import SwiftData

// MARK: - Days Since Last Lesson

extension PresentationsViewModel {
    func calculateDaysSinceLastLesson(
        lessonAssignments: [LessonAssignment],
        lessons: [Lesson],
        students: [Student]
    ) {
        var result: [UUID: Int] = [:]

        func norm(_ s: String) -> String {
            s.trimmed().lowercased()
        }

        let excludedLessonIDs: Set<UUID> = {
            let ids = lessons.filter { l in
                let s = norm(l.subject)
                let g = norm(l.group)
                return s == "parsha" || g == "parsha"
            }.map(\.id)
            return Set(ids)
        }()

        let given = lessonAssignments.filter {
            $0.isGiven && !excludedLessonIDs.contains($0.resolvedLessonID)
        }

        let lessonsByID = Dictionary(lessons.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let (lastDateByStudent, lastLessonIDByStudent) = buildLastLessonData(from: given)

        var subjects: [UUID: String] = [:]
        for s in students {
            if let last = lastDateByStudent[s.id] {
                guard let modelContext else { continue }
                let days = LessonAgeHelper.schoolDaysSinceCreation(
                    createdAt: last,
                    asOf: Date(),
                    using: modelContext,
                    calendar: calendar
                )
                result[s.id] = days
            } else {
                result[s.id] = Int.max
            }
            if let lessonID = lastLessonIDByStudent[s.id],
               let subject = lessonsByID[lessonID]?.subject,
               !subject.isEmpty {
                subjects[s.id] = subject
            }
        }

        self.daysSinceLastLessonByStudent = result
        self.lastSubjectByStudent = subjects
    }

    func buildLastLessonData(
        from given: [LessonAssignment]
    ) -> (dateByStudent: [UUID: Date], lessonIDByStudent: [UUID: UUID]) {
        var lastDateByStudent: [UUID: Date] = [:]
        var lastLessonIDByStudent: [UUID: UUID] = [:]
        for la in given {
            let when = la.presentedAt ?? la.scheduledFor ?? la.createdAt
            for sid in la.resolvedStudentIDs {
                if let existing = lastDateByStudent[sid] {
                    if when > existing {
                        lastDateByStudent[sid] = when
                        lastLessonIDByStudent[sid] = la.resolvedLessonID
                    }
                } else {
                    lastDateByStudent[sid] = when
                    lastLessonIDByStudent[sid] = la.resolvedLessonID
                }
            }
        }
        return (lastDateByStudent, lastLessonIDByStudent)
    }
}
