import CoreData
import Foundation

// MARK: - Fake classroom records

extension SampleClassroomSeeder {
    private struct FakeStudent {
        let id: UUID
        let firstName: String
        let lastName: String
        let age: Int
        let birthMonth: Int
        let birthDay: Int
        let level: CDStudent.Level
    }

    private static let fakeStudents: [FakeStudent] = [
        .init(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000001")!,
            firstName: "Ari", lastName: "Cedar", age: 7, birthMonth: 10, birthDay: 8, level: .lower
        ),
        .init(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000002")!,
            firstName: "Maya", lastName: "Stone", age: 8, birthMonth: 2, birthDay: 14, level: .lower
        ),
        .init(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000003")!,
            firstName: "Noah", lastName: "Linden", age: 8, birthMonth: 6, birthDay: 3, level: .lower
        ),
        .init(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000004")!,
            firstName: "Leah", lastName: "Hart", age: 9, birthMonth: 12, birthDay: 19, level: .lower
        ),
        .init(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000005")!,
            firstName: "Ezra", lastName: "Bloom", age: 10, birthMonth: 4, birthDay: 25, level: .upper
        ),
        .init(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000006")!,
            firstName: "Tamar", lastName: "Reed", age: 10, birthMonth: 9, birthDay: 11, level: .upper
        ),
        .init(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000007")!,
            firstName: "Miriam", lastName: "Vale", age: 11, birthMonth: 1, birthDay: 30, level: .upper
        ),
        .init(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000008")!,
            firstName: "Eli", lastName: "Brooks", age: 11, birthMonth: 7, birthDay: 17, level: .upper
        ),
        .init(
            id: UUID(uuidString: "A0000000-0000-0000-0000-000000000009")!,
            firstName: "Rina", lastName: "Ash", age: 12, birthMonth: 3, birthDay: 22, level: .adolescent
        )
    ]

    static func seedStudentsIfNeeded(
        in context: NSManagedObjectContext,
        now: Date,
        calendar: Calendar
    ) throws {
        guard try context.count(for: CDFetchRequest(CDStudent.self)) == 0 else { return }

        let currentYear = calendar.component(.year, from: now)
        for (index, seed) in fakeStudents.enumerated() {
            let student = CDStudent(context: context)
            student.id = seed.id
            student.firstName = seed.firstName
            student.lastName = seed.lastName
            student.level = seed.level
            student.manualOrder = Int64(index)
            student.birthday = calendar.date(from: DateComponents(
                year: currentYear - seed.age,
                month: seed.birthMonth,
                day: seed.birthDay
            ))
            student.dateStarted = calendar.date(byAdding: .month, value: -(index + 1), to: now)
            student.modifiedAt = now
        }
    }

    static func seedAttendanceIfNeeded(
        in context: NSManagedObjectContext,
        now: Date,
        calendar: Calendar
    ) throws {
        let request = CDFetchRequest(CDAttendanceRecord.self)
        guard try context.count(for: request) == 0 else { return }

        let today = calendar.startOfDay(for: now)
        for dayOffset in 0..<5 {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { continue }
            for (index, studentSeed) in fakeStudents.enumerated() {
                let record = CDAttendanceRecord(context: context)
                record.studentIDUUID = studentSeed.id
                record.date = day

                if dayOffset == 0 && index == 3 {
                    record.status = .absent
                    record.absenceReason = .sick
                } else if dayOffset == 0 && index == 6 {
                    record.status = .tardy
                } else if dayOffset == 2 && index == 1 {
                    record.status = .absent
                    record.absenceReason = .vacation
                } else {
                    record.status = .present
                }
            }
        }
    }

    static func seedLessonActivityIfNeeded(
        lessons: [LessonSnapshot],
        in context: NSManagedObjectContext,
        now: Date,
        calendar: Calendar
    ) throws {
        guard !lessons.isEmpty else { return }

        let historyRequest = CDFetchRequest(CDLessonPresentation.self)
        if try context.count(for: historyRequest) == 0 {
            for (studentIndex, studentSeed) in fakeStudents.enumerated() {
                for lessonOffset in 0..<min(3, lessons.count) {
                    let lesson = lessons[(studentIndex + lessonOffset) % lessons.count]
                    let history = CDLessonPresentation(context: context)
                    history.studentID = studentSeed.id.uuidString
                    history.lessonID = lesson.id.uuidString
                    history.presentedAt = calendar.date(
                        byAdding: .day,
                        value: -(studentIndex * 3 + lessonOffset + 2),
                        to: now
                    )
                    history.createdAt = history.presentedAt
                    history.state = lessonOffset == 0 ? .proficient : .presented
                    history.masteredAt = lessonOffset == 0 ? history.presentedAt : nil
                    history.notes = lessonOffset == 0
                        ? "Worked independently and explained the key idea clearly."
                        : "Sample presentation record for exploring the student timeline."
                }
            }
        }

        let assignmentRequest = CDFetchRequest(CDLessonAssignment.self)
        guard try context.count(for: assignmentRequest) == 0 else { return }

        let presentedGroups = Array(lessons.prefix(2))
        for (index, lesson) in presentedGroups.enumerated() {
            let assignment = CDLessonAssignment(context: context)
            assignment.lessonID = lesson.id.uuidString
            assignment.studentIDs = fakeStudents
                .dropFirst(index * 2)
                .prefix(3)
                .map { $0.id.uuidString }
            assignment.lessonTitleSnapshot = lesson.name
            assignment.lessonSectionSnapshot = lesson.section
            assignment.presentedAt = calendar.date(byAdding: .day, value: -(index + 1), to: now)
            assignment.state = .presented
            assignment.notes = "Sample small-group presentation."
        }

        for (index, lesson) in lessons.dropFirst(2).prefix(3).enumerated() {
            let assignment = CDLessonAssignment(context: context)
            assignment.lessonID = lesson.id.uuidString
            assignment.studentIDs = [fakeStudents[(index + 4) % fakeStudents.count].id.uuidString]
            assignment.lessonTitleSnapshot = lesson.name
            assignment.lessonSectionSnapshot = lesson.section
            if let scheduledDate = calendar.date(byAdding: .day, value: index, to: now) {
                // Sample data expresses a day, not a seed-run timestamp.
                assignment.schedule(onDay: scheduledDate, using: calendar)
            }
            assignment.notes = "Sample plan—safe to reschedule or complete."
        }
    }

    static func seedNotesIfNeeded(
        in context: NSManagedObjectContext,
        now: Date,
        calendar: Calendar
    ) throws {
        let request = CDFetchRequest(CDNote.self)
        guard try context.count(for: request) == 0 else { return }

        let bodies = [
            "Chose a challenging follow-up and stayed with it through two revisions.",
            "Asked to repeat yesterday's lesson with a partner and took the lead calmly.",
            "Needed a quieter workspace, then returned and completed the planned work.",
            "Connected today's lesson to an earlier story during group reflection.",
            "Showed careful material care while helping a younger classmate reset the shelf.",
            "Recorded a question to bring back to the next conference.",
            "Worked independently for a longer cycle than last week.",
            "Requested another presentation before beginning the follow-up work.",
            "Outlined a plan for a longer research project and set her own checkpoints."
        ]

        for (index, studentSeed) in fakeStudents.enumerated() {
            let note = CDNote(context: context)
            note.body = bodies[index]
            note.scope = .student(studentSeed.id)
            note.category = index == 2 ? .emotional : .academic
            note.tagsArray = index.isMultiple(of: 2) ? ["independence"] : ["follow-up"]
            note.createdAt = calendar.date(byAdding: .day, value: -index, to: now)
            note.updatedAt = note.createdAt
            note.needsFollowUp = index == 5 || index == 7

            let link = CDNoteStudentLink(context: context)
            link.noteIDUUID = note.id
            link.studentIDUUID = studentSeed.id
            link.note = note
        }
    }
}
