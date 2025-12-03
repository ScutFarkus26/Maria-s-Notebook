import Foundation

class WorkLookupService {
    let students: [Student]
    let lessons: [Lesson]
    let studentLessons: [StudentLesson]
    
    init(students: [Student], lessons: [Lesson], studentLessons: [StudentLesson]) {
        self.students = students
        self.lessons = lessons
        self.studentLessons = studentLessons
    }
    
    lazy var studentsByID: [UUID: Student] = {
        Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
    }()
    
    lazy var lessonsByID: [UUID: Lesson] = {
        Dictionary(uniqueKeysWithValues: lessons.map { ($0.id, $0) })
    }()
    
    lazy var studentLessonsByID: [UUID: StudentLesson] = {
        Dictionary(uniqueKeysWithValues: studentLessons.map { ($0.id, $0) })
    }()
    
    var subjects: [String] {
        let existing = Array(Set(lessons
            .map { $0.subject.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        )).sorted()
        return FilterOrderStore.loadSubjectOrder(existing: existing)
    }
    
    func linkedDate(for work: WorkModel) -> Date {
        if let slID = work.studentLessonID, let sl = studentLessonsByID[slID] {
            if let given = sl.givenAt { return given }
            if let sched = sl.scheduledFor { return sched }
        }
        return work.createdAt
    }
    
    func displayName(for student: Student) -> String {
        let parts = student.fullName.split(separator: " ")
        guard let first = parts.first else { return student.fullName }
        let lastInitial = parts.dropFirst().first?.first.map { String($0) } ?? ""
        return lastInitial.isEmpty ? String(first) : "\(first) \(lastInitial)."
    }
}
