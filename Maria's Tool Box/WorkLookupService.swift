import Foundation
import SwiftData

@available(*, deprecated, message: "WorkLookupService was part of the legacy WorkModel UI and is being phased out.")
struct WorkLookupService {
    let studentsByID: [UUID: Student]
    let lessonsByID: [UUID: Lesson]
    let studentLessonsByID: [UUID: StudentLesson]
    init(students: [Student], lessons: [Lesson], studentLessons: [StudentLesson]) {
        self.studentsByID = Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
        self.lessonsByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
        self.studentLessonsByID = Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) })
    }
}

