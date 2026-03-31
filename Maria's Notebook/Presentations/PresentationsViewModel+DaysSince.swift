// PresentationsViewModel+DaysSince.swift

import Foundation

// MARK: - Days Since Last CDLesson

extension PresentationsViewModel {
    func calculateDaysSinceLastLesson(
        lessonAssignments: [CDLessonAssignment],
        lessons: [CDLesson],
        students: [CDStudent]
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
            }.compactMap(\.id)
            return Set(ids)
        }()

        let given = lessonAssignments.filter {
            $0.isGiven && !excludedLessonIDs.contains($0.resolvedLessonID)
        }

        let lessonsByID: [UUID: CDLesson] = Dictionary(uniqueKeysWithValues: lessons.compactMap { lesson in guard let id = lesson.id else { return nil }; return (id, lesson) })

        let (lastDateByStudent, lastLessonIDByStudent) = buildLastLessonData(from: given)

        var subjects: [UUID: String] = [:]
        for s in students {
            guard let sid = s.id else { continue }
            if let last = lastDateByStudent[sid] {
                guard let viewContext else { continue }
                let days = LessonAgeHelper.schoolDaysSinceCreation(
                    createdAt: last,
                    asOf: Date(),
                    using: viewContext,
                    calendar: calendar
                )
                result[sid] = days
            } else {
                result[sid] = Int.max
            }
            if let lessonID = lastLessonIDByStudent[sid],
               let subject = lessonsByID[lessonID]?.subject,
               !subject.isEmpty {
                subjects[sid] = subject
            }
        }

        self.daysSinceLastLessonByStudent = result
        self.lastSubjectByStudent = subjects
    }

    func buildLastLessonData(
        from given: [CDLessonAssignment]
    ) -> (dateByStudent: [UUID: Date], lessonIDByStudent: [UUID: UUID]) {
        var lastDateByStudent: [UUID: Date] = [:]
        var lastLessonIDByStudent: [UUID: UUID] = [:]
        for la in given {
            let when = la.presentedAt ?? la.scheduledFor ?? la.createdAt ?? .distantPast
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
