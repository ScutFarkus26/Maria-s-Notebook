#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Work-Student Relationship Tests

@Suite("Work-Student Relationship Tests", .serialized)
@MainActor
struct WorkStudentRelationshipTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Student.self,
            Lesson.self,
            StudentLesson.self,
            Note.self,
        ])
    }

    @Test("WorkModel tracks single participant")
    func tracksSingleParticipant() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let work = WorkModel(title: "Math Practice", workType: .practice)
        let participant = WorkParticipantEntity(studentID: student.id, completedAt: nil, work: work)
        work.participants = [participant]
        context.insert(work)

        try context.save()

        #expect(work.participants?.count == 1)
        #expect(work.participants?.first?.studentID == student.id.uuidString)
    }

    @Test("WorkModel tracks multiple participants")
    func tracksMultipleParticipants() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        let student3 = makeTestStudent(firstName: "Charlie", lastName: "Clark")
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)

        let work = WorkModel(title: "Group Project", workType: .research)
        let p1 = WorkParticipantEntity(studentID: student1.id, completedAt: nil, work: work)
        let p2 = WorkParticipantEntity(studentID: student2.id, completedAt: nil, work: work)
        let p3 = WorkParticipantEntity(studentID: student3.id, completedAt: nil, work: work)
        work.participants = [p1, p2, p3]
        context.insert(work)

        try context.save()

        #expect(work.participants?.count == 3)
    }

    @Test("Participant completion tracked individually")
    func participantCompletionTrackedIndividually() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)

        let work = WorkModel(title: "Practice", workType: .practice)
        let p1 = WorkParticipantEntity(studentID: student1.id, completedAt: Date(), work: work)
        let p2 = WorkParticipantEntity(studentID: student2.id, completedAt: nil, work: work)
        work.participants = [p1, p2]
        context.insert(work)

        try context.save()

        #expect(work.isStudentCompleted(student1.id) == true)
        #expect(work.isStudentCompleted(student2.id) == false)
    }

    @Test("markStudent adds participant if not exists")
    func markStudentAddsParticipant() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let work = WorkModel(title: "Practice", workType: .practice)
        work.participants = []
        context.insert(work)

        work.markStudent(student.id, completedAt: Date())

        #expect(work.participants?.count == 1)
        #expect(work.isStudentCompleted(student.id) == true)
    }

    @Test("markStudent updates existing participant")
    func markStudentUpdatesExisting() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let work = WorkModel(title: "Practice", workType: .practice)
        let participant = WorkParticipantEntity(studentID: student.id, completedAt: nil, work: work)
        work.participants = [participant]
        context.insert(work)

        #expect(work.isStudentCompleted(student.id) == false)

        work.markStudent(student.id, completedAt: Date())

        #expect(work.isStudentCompleted(student.id) == true)
        #expect(work.participants?.count == 1) // Should not add duplicate
    }

    @Test("participant(for:) returns correct participant")
    func participantForReturnsCorrect() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        context.insert(student1)
        context.insert(student2)

        let work = WorkModel(title: "Practice", workType: .practice)
        let p1 = WorkParticipantEntity(studentID: student1.id, completedAt: nil, work: work)
        let p2 = WorkParticipantEntity(studentID: student2.id, completedAt: Date(), work: work)
        work.participants = [p1, p2]
        context.insert(work)

        let foundParticipant = work.participant(for: student2.id)

        #expect(foundParticipant?.studentID == student2.id.uuidString)
        #expect(foundParticipant?.completedAt != nil)
    }

    @Test("participant(for:) returns nil for unknown student")
    func participantForReturnsNilForUnknown() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Practice", workType: .practice)
        work.participants = []
        context.insert(work)

        let unknownID = UUID()
        let participant = work.participant(for: unknownID)

        #expect(participant == nil)
    }
}

// MARK: - Work Status Tests

@Suite("Work Status Integration Tests", .serialized)
@MainActor
struct WorkStatusIntegrationTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Note.self,
        ])
    }

    @Test("isOpen returns true for work with no participants")
    func isOpenTrueForNoParticipants() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "New Work", workType: .practice)
        work.participants = []
        context.insert(work)

        #expect(work.isOpen == true)
    }

    @Test("isOpen returns true when any participant incomplete")
    func isOpenTrueWhenAnyIncomplete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Practice", workType: .practice)
        let p1 = WorkParticipantEntity(studentID: UUID(), completedAt: Date(), work: work)
        let p2 = WorkParticipantEntity(studentID: UUID(), completedAt: nil, work: work)
        work.participants = [p1, p2]
        context.insert(work)

        #expect(work.isOpen == true)
    }

    @Test("isOpen returns false when all participants complete")
    func isOpenFalseWhenAllComplete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Practice", workType: .practice)
        let p1 = WorkParticipantEntity(studentID: UUID(), completedAt: Date(), work: work)
        let p2 = WorkParticipantEntity(studentID: UUID(), completedAt: Date(), work: work)
        work.participants = [p1, p2]
        context.insert(work)

        #expect(work.isOpen == false)
    }

    @Test("isOpen returns false when status is complete")
    func isOpenFalseWhenStatusComplete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Practice", workType: .practice, status: .complete)
        work.participants = []
        context.insert(work)

        #expect(work.isOpen == false)
    }

    @Test("Work status helpers are consistent")
    func statusHelpersAreConsistent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Practice", workType: .practice)
        context.insert(work)

        // Active status
        work.status = .active
        #expect(work.isActive == true)
        #expect(work.isReview == false)
        #expect(work.isComplete == false)
        #expect(work.isIncomplete == true)

        // Review status
        work.status = .review
        #expect(work.isActive == false)
        #expect(work.isReview == true)
        #expect(work.isComplete == false)
        #expect(work.isIncomplete == true)

        // Complete status
        work.status = .complete
        #expect(work.isActive == false)
        #expect(work.isReview == false)
        #expect(work.isComplete == true)
        #expect(work.isIncomplete == false)
    }
}

// MARK: - Work-Lesson Relationship Tests

@Suite("Work-Lesson Relationship Tests", .serialized)
@MainActor
struct WorkLessonRelationshipTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Lesson.self,
            StudentLesson.self,
            Student.self,
            Note.self,
        ])
    }

    @Test("Work links to lesson via lessonID")
    func workLinksToLesson() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let work = WorkModel(title: "Addition Practice", workType: .practice, lessonID: lesson.id.uuidString)
        context.insert(work)

        try context.save()

        #expect(work.lessonID == lesson.id.uuidString)
    }

    @Test("Work links to StudentLesson via studentLessonID")
    func workLinksToStudentLesson() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        context.insert(student)

        let studentLesson = makeTestStudentLesson(student: student, lesson: lesson, givenAt: Date())
        context.insert(studentLesson)

        let work = WorkModel(title: "Addition Practice", workType: .practice, studentLessonID: studentLesson.id)
        context.insert(work)

        try context.save()

        #expect(work.studentLessonID == studentLesson.id)
    }

    @Test("Multiple works can reference same lesson")
    func multipleWorksReferenceSameLesson() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        context.insert(lesson)

        let work1 = WorkModel(title: "Practice 1", workType: .practice, lessonID: lesson.id.uuidString)
        let work2 = WorkModel(title: "Practice 2", workType: .practice, lessonID: lesson.id.uuidString)
        let work3 = WorkModel(title: "Research", workType: .research, lessonID: lesson.id.uuidString)
        context.insert(work1)
        context.insert(work2)
        context.insert(work3)

        try context.save()

        #expect(work1.lessonID == lesson.id.uuidString)
        #expect(work2.lessonID == lesson.id.uuidString)
        #expect(work3.lessonID == lesson.id.uuidString)
    }
}

// MARK: - WorkCheckIn Integration Tests

@Suite("WorkCheckIn Integration Tests", .serialized)
@MainActor
struct WorkCheckInIntegrationTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Note.self,
        ])
    }

    @Test("addCheckIn creates check-in linked to work")
    func addCheckInCreatesLinkedCheckIn() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Practice", workType: .practice)
        context.insert(work)

        work.addCheckIn(date: Date(), status: .scheduled, purpose: "Review progress", in: context)

        try context.save()

        #expect(work.checkIns?.count == 1)
        #expect(work.checkIns?.first?.work?.id == work.id)
        #expect(work.checkIns?.first?.purpose == "Review progress")
    }

    @Test("scheduleCheckIn returns created check-in")
    func scheduleCheckInReturnsCreated() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Practice", workType: .practice)
        context.insert(work)

        let checkIn = work.scheduleCheckIn(on: Date(), purpose: "Follow up", in: context)

        #expect(checkIn.status == .scheduled)
        #expect(checkIn.purpose == "Follow up")
        #expect(checkIn.work?.id == work.id)
    }

    @Test("Multiple check-ins can be added to work")
    func multipleCheckInsCanBeAdded() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Practice", workType: .practice)
        context.insert(work)

        let date1 = TestCalendar.date(year: 2025, month: 3, day: 10)
        let date2 = TestCalendar.date(year: 2025, month: 3, day: 15)
        let date3 = TestCalendar.date(year: 2025, month: 3, day: 20)

        work.addCheckIn(date: date1, status: .completed, purpose: "Initial check", in: context)
        work.addCheckIn(date: date2, status: .completed, purpose: "Mid-point review", in: context)
        work.addCheckIn(date: date3, status: .scheduled, purpose: "Final review", in: context)

        try context.save()

        #expect(work.checkIns?.count == 3)
    }

    @Test("WorkCheckIn status can be updated")
    func checkInStatusCanBeUpdated() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Practice", workType: .practice)
        context.insert(work)

        let checkIn = work.scheduleCheckIn(on: Date(), purpose: "Review", in: context)

        #expect(checkIn.isScheduled == true)
        #expect(checkIn.isCompleted == false)

        checkIn.markCompleted(note: "Good progress", at: Date(), in: context)

        #expect(checkIn.isScheduled == false)
        #expect(checkIn.isCompleted == true)
        #expect(checkIn.note == "Good progress")
    }

    @Test("WorkCheckIn can be rescheduled")
    func checkInCanBeRescheduled() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Practice", workType: .practice)
        context.insert(work)

        let originalDate = TestCalendar.date(year: 2025, month: 3, day: 10)
        let newDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let checkIn = work.scheduleCheckIn(on: originalDate, purpose: "Review", in: context)
        checkIn.reschedule(to: newDate, note: "Moved to next week", in: context)

        let components = Calendar.current.dateComponents([.day], from: checkIn.date)
        #expect(components.day == 15)
        #expect(checkIn.note == "Moved to next week")
    }

    @Test("WorkCheckIn can be skipped")
    func checkInCanBeSkipped() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Practice", workType: .practice)
        context.insert(work)

        let checkIn = work.scheduleCheckIn(on: Date(), purpose: "Review", in: context)
        checkIn.skip(note: "Student absent", at: Date(), in: context)

        #expect(checkIn.status == .skipped)
        #expect(checkIn.note == "Student absent")
    }
}

// MARK: - WorkCheckInStatus Tests

@Suite("WorkCheckInStatus Tests", .serialized)
struct WorkCheckInStatusTests {

    @Test("WorkCheckInStatus has all expected cases")
    func hasAllExpectedCases() {
        let allCases = WorkCheckInStatus.allCases

        #expect(allCases.contains(.scheduled))
        #expect(allCases.contains(.completed))
        #expect(allCases.contains(.skipped))
        #expect(allCases.count == 3)
    }

    @Test("WorkCheckInStatus rawValues are correct")
    func rawValuesAreCorrect() {
        #expect(WorkCheckInStatus.scheduled.rawValue == "Scheduled")
        #expect(WorkCheckInStatus.completed.rawValue == "Completed")
        #expect(WorkCheckInStatus.skipped.rawValue == "Skipped")
    }
}

// MARK: - Work Type Tests

@Suite("WorkModel WorkType Tests", .serialized)
struct WorkModelWorkTypeTests {

    @Test("WorkType has all expected cases")
    func hasAllExpectedCases() {
        let allCases = WorkModel.WorkType.allCases

        #expect(allCases.contains(.research))
        #expect(allCases.contains(.followUp))
        #expect(allCases.contains(.practice))
        #expect(allCases.contains(.report))
        #expect(allCases.count == 4)
    }

    @Test("WorkType rawValues are correct")
    func rawValuesAreCorrect() {
        #expect(WorkModel.WorkType.research.rawValue == "Research")
        #expect(WorkModel.WorkType.followUp.rawValue == "Follow Up")
        #expect(WorkModel.WorkType.practice.rawValue == "Practice")
        #expect(WorkModel.WorkType.report.rawValue == "Report")
    }

    @Test("WorkModel workType getter/setter works")
    func workTypeGetterSetterWorks() {
        let work = WorkModel(title: "Test", workType: .research)

        #expect(work.workType == .research)

        work.workType = .practice
        #expect(work.workType == .practice)

        work.workType = .followUp
        #expect(work.workType == .followUp)
    }
}

// MARK: - WorkParticipantEntity Tests

@Suite("WorkParticipantEntity Tests", .serialized)
@MainActor
struct WorkParticipantEntityTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Note.self,
        ])
    }

    @Test("WorkParticipantEntity initializes correctly")
    func initializesCorrectly() {
        let studentID = UUID()
        let participant = WorkParticipantEntity(studentID: studentID, completedAt: nil)

        #expect(participant.studentID == studentID.uuidString)
        #expect(participant.completedAt == nil)
    }

    @Test("WorkParticipantEntity studentIDUUID computed property works")
    func studentIDUUIDWorks() {
        let studentID = UUID()
        let participant = WorkParticipantEntity(studentID: studentID, completedAt: nil)

        #expect(participant.studentIDUUID == studentID)

        let newID = UUID()
        participant.studentIDUUID = newID
        #expect(participant.studentIDUUID == newID)
    }

    @Test("WorkParticipantEntity persists correctly")
    func persistsCorrectly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let completionDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let work = WorkModel(title: "Test", workType: .practice)
        let participant = WorkParticipantEntity(studentID: studentID, completedAt: completionDate, work: work)
        work.participants = [participant]
        context.insert(work)

        try context.save()

        // Fetch and filter to avoid UUID predicate issues
        let workDescriptor = FetchDescriptor<WorkModel>()
        let fetched = try context.fetch(workDescriptor).first { $0.id == work.id }

        #expect(fetched?.participants?.count == 1)
        #expect(fetched?.participants?.first?.studentID == studentID.uuidString)
        #expect(fetched?.participants?.first?.completedAt != nil)
    }

    @Test("WorkParticipantEntity cascade deletes with work")
    func cascadeDeletesWithWork() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test", workType: .practice)
        let participant = WorkParticipantEntity(studentID: UUID(), completedAt: nil, work: work)
        work.participants = [participant]
        context.insert(work)

        try context.save()

        let participantID = participant.id
        context.delete(work)
        try context.save()

        // Fetch and filter to avoid UUID predicate issues
        let descriptor = FetchDescriptor<WorkParticipantEntity>()
        let fetched = try context.fetch(descriptor).filter { $0.id == participantID }

        #expect(fetched.isEmpty)
    }
}

// MARK: - Work Persistence Tests

@Suite("Work Persistence Tests", .serialized)
@MainActor
struct WorkPersistenceTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Note.self,
        ])
    }

    @Test("WorkModel persists all fields correctly")
    func persistsAllFieldsCorrectly() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let workID = UUID()
        let studentLessonID = UUID()
        let studentID = UUID()
        let lessonID = UUID()
        let assignedAt = TestCalendar.date(year: 2025, month: 3, day: 10)
        let dueAt = TestCalendar.date(year: 2025, month: 3, day: 20)

        let work = WorkModel(
            id: workID,
            title: "Complex Work",
            workType: .followUp,
            studentLessonID: studentLessonID,
            notes: "Important notes",
            status: .review,
            assignedAt: assignedAt,
            dueAt: dueAt,
            studentID: studentID.uuidString,
            lessonID: lessonID.uuidString
        )
        context.insert(work)

        try context.save()

        // Fetch and filter to avoid UUID predicate issues
        let descriptor = FetchDescriptor<WorkModel>()
        let fetched = try context.fetch(descriptor).first { $0.id == workID }

        #expect(fetched?.title == "Complex Work")
        #expect(fetched?.workType == .followUp)
        #expect(fetched?.studentLessonID == studentLessonID)
        #expect(fetched?.notes == "Important notes")
        #expect(fetched?.status == .review)
        #expect(fetched?.studentID == studentID.uuidString)
        #expect(fetched?.lessonID == lessonID.uuidString)
    }

    @Test("WorkModel handles nil optional fields")
    func handlesNilOptionalFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(
            title: "Simple Work",
            workType: .practice,
            studentLessonID: nil,
            dueAt: nil,
            completionOutcome: nil
        )
        context.insert(work)

        try context.save()

        // Fetch and filter to avoid UUID predicate issues
        let workDescriptor = FetchDescriptor<WorkModel>()
        let fetched = try context.fetch(workDescriptor).first { $0.id == work.id }

        #expect(fetched?.studentLessonID == nil)
        #expect(fetched?.dueAt == nil)
        #expect(fetched?.completionOutcome == nil)
    }

    @Test("WorkModel checkIns cascade delete")
    func checkInsCascadeDelete() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = WorkModel(title: "Test", workType: .practice)
        context.insert(work)

        work.addCheckIn(date: Date(), status: .scheduled, purpose: "Check 1", in: context)
        work.addCheckIn(date: Date(), status: .scheduled, purpose: "Check 2", in: context)

        try context.save()

        let checkInID = work.checkIns?.first?.id ?? UUID()

        context.delete(work)
        try context.save()

        // Fetch and filter to avoid UUID predicate issues
        let checkInDescriptor = FetchDescriptor<WorkCheckIn>()
        let fetched = try context.fetch(checkInDescriptor).filter { $0.id == checkInID }

        #expect(fetched.isEmpty)
    }
}

#endif
