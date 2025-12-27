import Foundation
import SwiftData

/// A service that provides lookup dictionaries and convenience helpers
/// to efficiently access and resolve related work, student, and lesson data.
struct WorkLookupService {
    let studentsByID: [UUID: Student]
    let lessonsByID: [UUID: Lesson]
    let studentLessonsByID: [UUID: StudentLesson]
    
    /// Initializes the service with arrays of students, lessons, and student lessons,
    /// organizing them into dictionaries keyed by their respective UUIDs.
    init(students: [Student], lessons: [Lesson], studentLessons: [StudentLesson]) {
        self.studentsByID = Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
        self.lessonsByID = Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
        self.studentLessonsByID = Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) })
    }
    
    /// Returns the title for a given work model.
    /// If the work's title is non-empty, returns it.
    /// Otherwise, if the studentLessonID resolves to a lesson, returns that lesson's name.
    /// Otherwise, returns the raw value of the work's workType.
    func title(for work: WorkModel) -> String {
        if !work.title.isEmpty {
            return work.title
        }
        if let studentLessonID = work.studentLessonID,
           let studentLesson = studentLessonsByID[studentLessonID],
           let lesson = lessonsByID[studentLesson.lessonID] {
            return lesson.name
        }
        return work.workType.rawValue
    }
}
