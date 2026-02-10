#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Test Context Setup

@MainActor
private struct WorkTestContext {
    let container: ModelContainer
    let context: ModelContext

    static func make() throws -> WorkTestContext {
        let container = try makeTestContainer(for: [
            WorkModel.self, WorkParticipantEntity.self, WorkCheckIn.self,
            Student.self, Lesson.self, StudentLesson.self, Note.self,
        ])
        return WorkTestContext(container: container, context: ModelContext(container))
    }

    func makeWork(title: String = "Test Work", workType: WorkModel.WorkType = .practice) -> WorkModel {
        let work = WorkModel(title: title, workType: workType)
        context.insert(work)
        return work
    }

    func makeParticipant(for work: WorkModel, studentID: UUID, completedAt: Date? = nil) -> WorkParticipantEntity {
        let participant = WorkParticipantEntity(studentID: studentID, completedAt: completedAt, work: work)
        context.insert(participant)
        return participant
    }
}

// MARK: - Work-Student Relationship Tests

@Suite("Work-Student Relationship Tests", .serialized)
@MainActor
struct WorkStudentRelationshipTests {

    @Test("WorkModel tracks single participant")
    func tracksSingleParticipant() throws {
        let tc = try WorkTestContext.make()
        let student = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        tc.context.insert(student)

        let work = WorkModel(title: "Math Practice", workType: .practice)
        work.participants = [WorkParticipantEntity(studentID: student.id, completedAt: nil, work: work)]
        tc.context.insert(work)
        try tc.context.save()

        #expect(work.participants?.count == 1)
        #expect(work.participants?.first?.studentID == student.id.uuidString)
    }

    @Test("WorkModel tracks multiple participants")
    func tracksMultipleParticipants() throws {
        let tc = try WorkTestContext.make()
        let students = [
            makeTestStudent(firstName: "Alice", lastName: "Anderson"),
            makeTestStudent(firstName: "Bob", lastName: "Brown"),
            makeTestStudent(firstName: "Charlie", lastName: "Clark")
        ]
        students.forEach { tc.context.insert($0) }

        let work = WorkModel(title: "Group Project", workType: .research)
        work.participants = students.map { WorkParticipantEntity(studentID: $0.id, completedAt: nil, work: work) }
        tc.context.insert(work)
        try tc.context.save()

        #expect(work.participants?.count == 3)
    }

    @Test("Participant completion tracked individually")
    func participantCompletionTrackedIndividually() throws {
        let tc = try WorkTestContext.make()
        let student1 = makeTestStudent(firstName: "Alice", lastName: "Anderson")
        let student2 = makeTestStudent(firstName: "Bob", lastName: "Brown")
        tc.context.insert(student1)
        tc.context.insert(student2)

        let work = WorkModel(title: "Practice", workType: .practice)
        work.participants = [
            WorkParticipantEntity(studentID: student1.id, completedAt: Date(), work: work),
            WorkParticipantEntity(studentID: student2.id, completedAt: nil, work: work)
        ]
        tc.context.insert(work)
        try tc.context.save()

        #expect(work.isStudentCompleted(student1.id) == true)
        #expect(work.isStudentCompleted(student2.id) == false)
    }

    @Test("markStudent adds participant if not exists")
    func markStudentAddsParticipant() throws {
        let tc = try WorkTestContext.make()
        let student = makeTestStudent()
        tc.context.insert(student)

        let work = tc.makeWork()
        work.participants = []
        work.markStudent(student.id, completedAt: Date())

        #expect(work.participants?.count == 1)
        #expect(work.isStudentCompleted(student.id) == true)
    }

    @Test("markStudent updates existing participant")
    func markStudentUpdatesExisting() throws {
        let tc = try WorkTestContext.make()
        let student = makeTestStudent()
        tc.context.insert(student)

        let work = tc.makeWork()
        let participant = tc.makeParticipant(for: work, studentID: student.id)
        work.participants = [participant]

        #expect(work.isStudentCompleted(student.id) == false)

        work.markStudent(student.id, completedAt: Date())

        #expect(work.isStudentCompleted(student.id) == true)
        #expect(work.participants?.count == 1)
    }

    @Test("participant(for:) returns correct participant")
    func participantForReturnsCorrect() throws {
        let tc = try WorkTestContext.make()
        let student1 = makeTestStudent()
        let student2 = makeTestStudent()
        tc.context.insert(student1)
        tc.context.insert(student2)

        let work = tc.makeWork()
        work.participants = [
            tc.makeParticipant(for: work, studentID: student1.id),
            tc.makeParticipant(for: work, studentID: student2.id, completedAt: Date())
        ]

        let foundParticipant = work.participant(for: student2.id)

        #expect(foundParticipant?.studentID == student2.id.uuidString)
        #expect(foundParticipant?.completedAt != nil)
    }

    @Test("participant(for:) returns nil for unknown student")
    func participantForReturnsNilForUnknown() throws {
        let tc = try WorkTestContext.make()
        let work = tc.makeWork()
        work.participants = []

        #expect(work.participant(for: UUID()) == nil)
    }
}

// MARK: - Work Status Tests

@Suite("Work Status Integration Tests", .serialized)
@MainActor
struct WorkStatusIntegrationTests {

    @Test("isOpen returns true for work with no participants")
    func isOpenTrueForNoParticipants() throws {
        let tc = try WorkTestContext.make()
        let work = tc.makeWork()
        work.participants = []

        #expect(work.isOpen == true)
    }

    @Test("isOpen returns true when any participant incomplete")
    func isOpenTrueWhenAnyIncomplete() throws {
        let tc = try WorkTestContext.make()
        let work = tc.makeWork()
        work.participants = [
            WorkParticipantEntity(studentID: UUID(), completedAt: Date(), work: work),
            WorkParticipantEntity(studentID: UUID(), completedAt: nil, work: work)
        ]

        #expect(work.isOpen == true)
    }

    @Test("isOpen returns false when all participants complete")
    func isOpenFalseWhenAllComplete() throws {
        let tc = try WorkTestContext.make()
        let work = tc.makeWork()
        work.participants = [
            WorkParticipantEntity(studentID: UUID(), completedAt: Date(), work: work),
            WorkParticipantEntity(studentID: UUID(), completedAt: Date(), work: work)
        ]

        #expect(work.isOpen == false)
    }

    @Test("isOpen returns false when status is complete")
    func isOpenFalseWhenStatusComplete() throws {
        let tc = try WorkTestContext.make()
        let work = WorkModel(title: "Practice", workType: .practice, status: .complete)
        tc.context.insert(work)

        #expect(work.isOpen == false)
    }

    @Test("Work status helpers are consistent")
    func statusHelpersAreConsistent() throws {
        let tc = try WorkTestContext.make()
        let work = tc.makeWork()

        work.status = .active
        #expect(work.isActive == true)
        #expect(work.isReview == false)
        #expect(work.isComplete == false)
        #expect(work.isIncomplete == true)

        work.status = .review
        #expect(work.isActive == false)
        #expect(work.isReview == true)
        #expect(work.isComplete == false)
        #expect(work.isIncomplete == true)

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

    @Test("Work links to lesson via lessonID")
    func workLinksToLesson() throws {
        let tc = try WorkTestContext.make()
        let lesson = makeTestLesson(name: "Addition", subject: "Math", group: "Operations")
        tc.context.insert(lesson)

        let work = WorkModel(title: "Addition Practice", workType: .practice, lessonID: lesson.id.uuidString)
        tc.context.insert(work)
        try tc.context.save()

        #expect(work.lessonID == lesson.id.uuidString)
    }

    @Test("Work links to StudentLesson via studentLessonID")
    func workLinksToStudentLesson() throws {
        let tc = try WorkTestContext.make()
        let lesson = makeTestLesson()
        let student = makeTestStudent()
        tc.context.insert(lesson)
        tc.context.insert(student)

        let studentLesson = makeTestStudentLesson(student: student, lesson: lesson, givenAt: Date())
        tc.context.insert(studentLesson)

        let work = WorkModel(title: "Addition Practice", workType: .practice, studentLessonID: studentLesson.id)
        tc.context.insert(work)
        try tc.context.save()

        #expect(work.studentLessonID == studentLesson.id)
    }

    @Test("Multiple works can reference same lesson")
    func multipleWorksReferenceSameLesson() throws {
        let tc = try WorkTestContext.make()
        let lesson = makeTestLesson()
        tc.context.insert(lesson)

        let works = [
            WorkModel(title: "Practice 1", workType: .practice, lessonID: lesson.id.uuidString),
            WorkModel(title: "Practice 2", workType: .practice, lessonID: lesson.id.uuidString),
            WorkModel(title: "Research", workType: .research, lessonID: lesson.id.uuidString)
        ]
        works.forEach { tc.context.insert($0) }
        try tc.context.save()

        #expect(works.allSatisfy { $0.lessonID == lesson.id.uuidString })
    }
}

// MARK: - WorkCheckIn Integration Tests

@Suite("WorkCheckIn Integration Tests", .serialized)
@MainActor
struct WorkCheckInIntegrationTests {

    @Test("addCheckIn creates check-in linked to work")
    func addCheckInCreatesLinkedCheckIn() throws {
        let tc = try WorkTestContext.make()
        let work = tc.makeWork()

        work.addCheckIn(date: Date(), status: .scheduled, purpose: "Review progress", in: tc.context)
        try tc.context.save()

        #expect(work.checkIns?.count == 1)
        #expect(work.checkIns?.first?.work?.id == work.id)
        #expect(work.checkIns?.first?.purpose == "Review progress")
    }

    @Test("scheduleCheckIn returns created check-in")
    func scheduleCheckInReturnsCreated() throws {
        let tc = try WorkTestContext.make()
        let work = tc.makeWork()

        let checkIn = work.scheduleCheckIn(on: Date(), purpose: "Follow up", in: tc.context)

        #expect(checkIn.status == .scheduled)
        #expect(checkIn.purpose == "Follow up")
        #expect(checkIn.work?.id == work.id)
    }

    @Test("Multiple check-ins can be added to work")
    func multipleCheckInsCanBeAdded() throws {
        let tc = try WorkTestContext.make()
        let work = tc.makeWork()

        let dates = [
            TestCalendar.date(year: 2025, month: 3, day: 10),
            TestCalendar.date(year: 2025, month: 3, day: 15),
            TestCalendar.date(year: 2025, month: 3, day: 20)
        ]
        let purposes = ["Initial check", "Mid-point review", "Final review"]
        let statuses: [WorkCheckInStatus] = [.completed, .completed, .scheduled]

        for (i, date) in dates.enumerated() {
            work.addCheckIn(date: date, status: statuses[i], purpose: purposes[i], in: tc.context)
        }
        try tc.context.save()

        #expect(work.checkIns?.count == 3)
    }

    @Test("WorkCheckIn status can be updated")
    func checkInStatusCanBeUpdated() throws {
        let tc = try WorkTestContext.make()
        let work = tc.makeWork()

        let checkIn = work.scheduleCheckIn(on: Date(), purpose: "Review", in: tc.context)

        #expect(checkIn.isScheduled == true)
        #expect(checkIn.isCompleted == false)

        checkIn.markCompleted(note: "Good progress", at: Date(), in: tc.context)

        #expect(checkIn.isScheduled == false)
        #expect(checkIn.isCompleted == true)
        #expect(checkIn.note == "Good progress")
    }

    @Test("WorkCheckIn can be rescheduled")
    func checkInCanBeRescheduled() throws {
        let tc = try WorkTestContext.make()
        let work = tc.makeWork()

        let originalDate = TestCalendar.date(year: 2025, month: 3, day: 10)
        let newDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let checkIn = work.scheduleCheckIn(on: originalDate, purpose: "Review", in: tc.context)
        checkIn.reschedule(to: newDate, note: "Moved to next week", in: tc.context)

        let components = Calendar.current.dateComponents([.day], from: checkIn.date)
        #expect(components.day == 15)
        #expect(checkIn.note == "Moved to next week")
    }

    @Test("WorkCheckIn can be skipped")
    func checkInCanBeSkipped() throws {
        let tc = try WorkTestContext.make()
        let work = tc.makeWork()

        let checkIn = work.scheduleCheckIn(on: Date(), purpose: "Review", in: tc.context)
        checkIn.skip(note: "Student absent", at: Date(), in: tc.context)

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
        let tc = try WorkTestContext.make()
        let studentID = UUID()
        let completionDate = TestCalendar.date(year: 2025, month: 3, day: 15)

        let work = tc.makeWork()
        let participant = tc.makeParticipant(for: work, studentID: studentID, completedAt: completionDate)
        work.participants = [participant]
        try tc.context.save()

        let workDescriptor = FetchDescriptor<WorkModel>()
        let fetched = try tc.context.fetch(workDescriptor).first { $0.id == work.id }

        #expect(fetched?.participants?.count == 1)
        #expect(fetched?.participants?.first?.studentID == studentID.uuidString)
        #expect(fetched?.participants?.first?.completedAt != nil)
    }

    @Test("WorkParticipantEntity cascade deletes with work")
    func cascadeDeletesWithWork() throws {
        let tc = try WorkTestContext.make()
        let work = tc.makeWork()
        let participant = tc.makeParticipant(for: work, studentID: UUID())
        work.participants = [participant]
        try tc.context.save()

        let participantID = participant.id
        tc.context.delete(work)
        try tc.context.save()

        let descriptor = FetchDescriptor<WorkParticipantEntity>()
        let fetched = try tc.context.fetch(descriptor).filter { $0.id == participantID }

        #expect(fetched.isEmpty)
    }
}

// MARK: - Work Persistence Tests

@Suite("Work Persistence Tests", .serialized)
@MainActor
struct WorkPersistenceTests {

    @Test("WorkModel persists all fields correctly")
    func persistsAllFieldsCorrectly() throws {
        let tc = try WorkTestContext.make()
        let workID = UUID()
        let studentLessonID = UUID()
        let studentID = UUID()
        let lessonID = UUID()
        let assignedAt = TestCalendar.date(year: 2025, month: 3, day: 10)
        let dueAt = TestCalendar.date(year: 2025, month: 3, day: 20)

        let work = WorkModel(
            id: workID, title: "Complex Work", workType: .followUp,
            studentLessonID: studentLessonID, notes: "Important notes",
            status: .review, assignedAt: assignedAt, dueAt: dueAt,
            studentID: studentID.uuidString, lessonID: lessonID.uuidString
        )
        tc.context.insert(work)
        try tc.context.save()

        let descriptor = FetchDescriptor<WorkModel>()
        let fetched = try tc.context.fetch(descriptor).first { $0.id == workID }

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
        let tc = try WorkTestContext.make()
        let work = WorkModel(
            title: "Simple Work", workType: .practice,
            studentLessonID: nil, dueAt: nil, completionOutcome: nil
        )
        tc.context.insert(work)
        try tc.context.save()

        let workDescriptor = FetchDescriptor<WorkModel>()
        let fetched = try tc.context.fetch(workDescriptor).first { $0.id == work.id }

        #expect(fetched?.studentLessonID == nil)
        #expect(fetched?.dueAt == nil)
        #expect(fetched?.completionOutcome == nil)
    }

    @Test("WorkModel checkIns cascade delete")
    func checkInsCascadeDelete() throws {
        let tc = try WorkTestContext.make()
        let work = tc.makeWork()

        work.addCheckIn(date: Date(), status: .scheduled, purpose: "Check 1", in: tc.context)
        work.addCheckIn(date: Date(), status: .scheduled, purpose: "Check 2", in: tc.context)
        try tc.context.save()

        let checkInID = work.checkIns?.first?.id ?? UUID()

        tc.context.delete(work)
        try tc.context.save()

        let checkInDescriptor = FetchDescriptor<WorkCheckIn>()
        let fetched = try tc.context.fetch(checkInDescriptor).filter { $0.id == checkInID }

        #expect(fetched.isEmpty)
    }
}

#endif
