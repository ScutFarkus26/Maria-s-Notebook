#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Orphaned Student ID Cleanup Tests

@Suite("DataCleanupService Orphaned StudentLesson IDs Tests", .serialized)
@MainActor
struct DataCleanupServiceOrphanedStudentLessonIDsTests {

    private static let commonModels: [any PersistentModel.Type] = [
        Student.self, Lesson.self, StudentLesson.self, LessonPresentation.self, Note.self
    ]

    private func makeContainer() throws -> ModelContainer {
        return try TestContainerFactory.makeContainer(for: Self.commonModels)
    }

    @Test("cleanOrphanedStudentIDs removes non-existent student IDs from StudentLesson")
    func cleanOrphanedStudentIDsRemovesNonExistent() async throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.commonModels)
        let builder = TestEntityBuilder(context: context)

        let validStudent = try builder.buildStudent(firstName: "Alice", lastName: "Smith")
        let orphanedID = UUID()
        let sl = makeTestStudentLesson(studentIDs: [validStudent.id, orphanedID])
        context.insert(sl)
        try context.save()

        await DataCleanupService.cleanOrphanedStudentIDs(using: context)

        TestPatterns.expectCount(sl.studentIDs, equals: 1)
        #expect(sl.studentIDs.contains(validStudent.id.uuidString))
        #expect(!sl.studentIDs.contains(orphanedID.uuidString))
    }

    @Test("cleanOrphanedStudentIDs preserves all valid student IDs")
    func cleanOrphanedStudentIDsPreservesValid() async throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.commonModels)
        let builder = TestEntityBuilder(context: context)

        let student1 = try builder.buildStudent(firstName: "Alice", lastName: "Smith")
        let student2 = try builder.buildStudent(firstName: "Bob", lastName: "Jones")
        let sl = makeTestStudentLesson(studentIDs: [student1.id, student2.id])
        context.insert(sl)
        try context.save()

        await DataCleanupService.cleanOrphanedStudentIDs(using: context)

        TestPatterns.expectCount(sl.studentIDs, equals: 2)
    }

    @Test("cleanOrphanedStudentIDs handles StudentLesson with no students")
    func cleanOrphanedStudentIDsHandlesEmpty() async throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.commonModels)

        let sl = makeTestStudentLesson(studentIDs: [])
        context.insert(sl)
        try context.save()

        await DataCleanupService.cleanOrphanedStudentIDs(using: context)

        TestPatterns.expectEmpty(sl.studentIDs)
    }

    @Test("cleanOrphanedStudentIDs is idempotent")
    func cleanOrphanedStudentIDsIsIdempotent() async throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.commonModels)
        let builder = TestEntityBuilder(context: context)

        let validStudent = try builder.buildStudent(firstName: "Alice", lastName: "Smith")
        let orphanedID = UUID()
        let sl = makeTestStudentLesson(studentIDs: [validStudent.id, orphanedID])
        context.insert(sl)
        try context.save()

        await DataCleanupService.cleanOrphanedStudentIDs(using: context)
        let firstCount = sl.studentIDs.count

        await DataCleanupService.cleanOrphanedStudentIDs(using: context)

        #expect(sl.studentIDs.count == firstCount)
        TestPatterns.expectCount(sl.studentIDs, equals: 1)
    }
}

// MARK: - Orphaned Work Student ID Cleanup Tests

@Suite("DataCleanupService Orphaned WorkModel IDs Tests", .serialized)
@MainActor
struct DataCleanupServiceOrphanedWorkModelIDsTests {

    private static let workModels: [any PersistentModel.Type] = [
        Student.self, WorkModel.self, WorkParticipantEntity.self, WorkCheckIn.self, Note.self
    ]

    @Test("cleanOrphanedWorkStudentIDs clears orphaned studentID")
    func cleanOrphanedWorkStudentIDsClearsOrphaned() async throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.workModels)
        let builder = TestEntityBuilder(context: context)

        let orphanedID = UUID()
        let work = try builder.buildWorkModel(studentID: orphanedID.uuidString)

        await DataCleanupService.cleanOrphanedWorkStudentIDs(using: context)

        #expect(work.studentID == "")
    }

    @Test("cleanOrphanedWorkStudentIDs preserves valid studentID")
    func cleanOrphanedWorkStudentIDsPreservesValid() async throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.workModels)
        let builder = TestEntityBuilder(context: context)

        let validStudent = try builder.buildStudent(firstName: "Alice", lastName: "Smith")
        let work = try builder.buildWorkModel(studentID: validStudent.id.uuidString)

        await DataCleanupService.cleanOrphanedWorkStudentIDs(using: context)

        #expect(work.studentID == validStudent.id.uuidString)
    }

    @Test("cleanOrphanedWorkStudentIDs removes orphaned participants")
    func cleanOrphanedWorkStudentIDsRemovesOrphanedParticipants() async throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.workModels)
        let builder = TestEntityBuilder(context: context)

        let validStudent = try builder.buildStudent(firstName: "Alice", lastName: "Smith")
        let work = try builder.buildWorkModel()
        let validParticipant = WorkParticipantEntity(studentID: validStudent.id, work: work)
        let orphanedParticipant = WorkParticipantEntity(studentID: UUID(), work: work)
        work.participants = [validParticipant, orphanedParticipant]
        try context.save()

        await DataCleanupService.cleanOrphanedWorkStudentIDs(using: context)

        TestPatterns.expectCount(work.participants ?? [], equals: 1)
        #expect(work.participants?[0].studentID == validStudent.id.uuidString)
    }

    @Test("cleanOrphanedWorkStudentIDs handles work with no participants")
    func cleanOrphanedWorkStudentIDsHandlesNoParticipants() async throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.workModels)
        let builder = TestEntityBuilder(context: context)

        let work = try builder.buildWorkModel()
        work.participants = []
        try context.save()

        await DataCleanupService.cleanOrphanedWorkStudentIDs(using: context)

        TestPatterns.expectEmpty(work.participants ?? [])
    }
}

// MARK: - Deduplication Tests

@Suite("DataCleanupService Deduplication Tests", .serialized)
@MainActor
struct DataCleanupServiceDeduplicationTests {

    private static let studentModels: [any PersistentModel.Type] = [
        Student.self, Lesson.self, StudentLesson.self, Note.self
    ]

    private static let projectModels: [any PersistentModel.Type] = [
        Project.self, ProjectSession.self, ProjectRole.self, Note.self
    ]

    @Test("deduplicate removes duplicate students with same ID")
    func deduplicateStudentsRemovesDuplicates() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.studentModels)

        try DeduplicationTester.testDeduplication(
            ofType: Student.self,
            setup: { ctx in
                let sharedID = UUID()
                let student1 = Student(
                    id: sharedID, firstName: "Alice", lastName: "Smith",
                    birthday: TestCalendar.date(year: 2015, month: 6, day: 15)
                )
                let student2 = Student(
                    id: sharedID, firstName: "Alice", lastName: "Smith",
                    birthday: TestCalendar.date(year: 2015, month: 6, day: 15)
                )
                ctx.insert(student1)
                ctx.insert(student2)
                try ctx.save()
            },
            deduplicateAction: { ctx in DataCleanupService.deduplicate(Student.self, using: ctx) },
            verifyDeletedCount: 1,
            verifyRemainingCount: 1,
            context: context
        )
    }

    @Test("deduplicate preserves unique students")
    func deduplicateStudentsPreservesUnique() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.studentModels)
        let builder = TestEntityBuilder(context: context)

        _ = try builder.buildStudent(firstName: "Alice", lastName: "Smith")
        _ = try builder.buildStudent(firstName: "Bob", lastName: "Jones")

        let deletedCount = DataCleanupService.deduplicate(Student.self, using: context)

        #expect(deletedCount == 0)
        let remaining = context.safeFetch(FetchDescriptor<Student>())
        TestPatterns.expectCount(remaining, equals: 2)
    }

    @Test("deduplicate removes duplicate projects with same ID")
    func deduplicateProjectsRemovesDuplicates() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.projectModels)

        let project1 = Project(title: "Book Club")
        let project2 = Project(title: "Book Club")
        context.insert(project1)
        context.insert(project2)
        try context.save()

        let deletedCount = DataCleanupService.deduplicate(Project.self, using: context)

        #expect(deletedCount == 0)
    }

    @Test("deduplicate removes duplicate roles")
    func deduplicateProjectRolesRemovesDuplicates() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.projectModels)

        let role1 = ProjectRole(projectID: UUID(), title: "Leader")
        let role2 = ProjectRole(projectID: UUID(), title: "Helper")
        context.insert(role1)
        context.insert(role2)
        try context.save()

        let deletedCount = DataCleanupService.deduplicate(ProjectRole.self, using: context)

        #expect(deletedCount == 0)
    }
}

// MARK: - Deduplication Merge Behavior Tests

@Suite("DataCleanupService Dedup Merge Tests", .serialized)
@MainActor
struct DataCleanupServiceDedupMergeTests {

    private static let allModels: [any PersistentModel.Type] = [
        Student.self, Document.self, Lesson.self, StudentLesson.self, LessonPresentation.self,
        Note.self, NoteStudentLink.self, WorkModel.self, WorkParticipantEntity.self,
        WorkCheckIn.self, WorkStep.self
    ]

    @Test("deduplicateStudentsStrong merges fields and documents")
    func deduplicateStudentsStrongMergesFieldsAndDocuments() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.allModels)

        let sharedID = UUID()
        let studentA = Student(
            id: sharedID,
            firstName: "Alice",
            lastName: "",
            birthday: TestCalendar.date(year: 2015, month: 6, day: 15)
        )
        let studentB = Student(
            id: sharedID,
            firstName: "",
            lastName: "Smith",
            birthday: TestCalendar.date(year: 2015, month: 6, day: 15)
        )

        let document = Document(id: UUID(), title: "Report", category: "Test", student: studentB)
        studentB.documents = [document]

        context.insert(studentA)
        context.insert(studentB)
        context.insert(document)
        try context.save()

        let deletedCount = DataCleanupService.deduplicateStudentsStrong(using: context)
        #expect(deletedCount == 1)

        let remaining = context.safeFetch(FetchDescriptor<Student>())
        TestPatterns.expectCount(remaining, equals: 1)

        let student = remaining[0]
        #expect(!student.firstName.isEmpty)
        #expect(!student.lastName.isEmpty)
        #expect(student.documents?.count == 1)
        #expect(student.documents?.first?.student?.id == student.id)
    }

    @Test("deduplicateLessonsStrong merges fields and relationships")
    func deduplicateLessonsStrongMergesFieldsAndRelationships() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.allModels)

        let sharedID = UUID()
        let lessonA = Lesson(id: sharedID, name: "Intro", subject: "Math", group: "", subheading: "", writeUp: "")
        let lessonB = Lesson(id: sharedID, name: "", subject: "", group: "Group A", subheading: "Sub", writeUp: "WriteUp")

        let note = Note(body: "Lesson note", scope: .all, lesson: lessonB)
        let studentLesson = StudentLesson(lesson: lessonB, students: [])

        context.insert(lessonA)
        context.insert(lessonB)
        context.insert(note)
        context.insert(studentLesson)
        try context.save()

        let deletedCount = DataCleanupService.deduplicateLessonsStrong(using: context)
        #expect(deletedCount == 1)

        let remaining = context.safeFetch(FetchDescriptor<Lesson>())
        TestPatterns.expectCount(remaining, equals: 1)

        let lesson = remaining[0]
        #expect(!lesson.name.isEmpty)
        #expect(!lesson.group.isEmpty)
        #expect(!lesson.subheading.isEmpty)
        #expect(!lesson.writeUp.isEmpty)
        #expect(lesson.notes?.count == 1)
        #expect(lesson.notes?.first?.lesson?.id == lesson.id)
        #expect(lesson.studentLessons?.count == 1)
        #expect(lesson.studentLessons?.first?.lesson?.id == lesson.id)
    }

    @Test("deduplicateLessonPresentationsStrong merges fields")
    func deduplicateLessonPresentationsStrongMergesFields() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.allModels)

        let sharedID = UUID()
        let lpA = LessonPresentation(
            id: sharedID,
            studentID: "student",
            lessonID: "lesson",
            notes: "Notes"
        )
        let lpB = LessonPresentation(
            id: sharedID,
            studentID: "",
            lessonID: "",
            presentationID: "presentation"
        )

        context.insert(lpA)
        context.insert(lpB)
        try context.save()

        let deletedCount = DataCleanupService.deduplicateLessonPresentationsStrong(using: context)
        #expect(deletedCount == 1)

        let remaining = context.safeFetch(FetchDescriptor<LessonPresentation>())
        TestPatterns.expectCount(remaining, equals: 1)

        let lp = remaining[0]
        #expect(!lp.studentID.isEmpty)
        #expect(!lp.lessonID.isEmpty)
        #expect(lp.presentationID == "presentation")
        #expect(lp.notes == "Notes")
    }

    @Test("deduplicateWorkModelsStrong merges fields and relationships")
    func deduplicateWorkModelsStrongMergesFieldsAndRelationships() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.allModels)

        let sharedID = UUID()
        let workA = WorkModel(id: sharedID, title: "Work A", notes: "")
        let workB = WorkModel(id: sharedID, title: "", notes: "Details")

        let participant = WorkParticipantEntity(studentID: UUID(), work: workB)
        let checkIn = WorkCheckIn(workID: workB.id, date: Date(), status: .scheduled, work: workB)
        let step = WorkStep(work: workB, orderIndex: 0, title: "Step", instructions: "Do the thing")
        let note = Note(body: "Work note", scope: .all, work: workB)

        workB.participants = [participant]
        workB.checkIns = [checkIn]
        workB.steps = [step]
        workB.unifiedNotes = [note]

        context.insert(workA)
        context.insert(workB)
        context.insert(participant)
        context.insert(checkIn)
        context.insert(step)
        context.insert(note)
        try context.save()

        let deletedCount = DataCleanupService.deduplicateWorkModelsStrong(using: context)
        #expect(deletedCount == 1)

        let remaining = context.safeFetch(FetchDescriptor<WorkModel>())
        TestPatterns.expectCount(remaining, equals: 1)

        let work = remaining[0]
        #expect(!work.title.isEmpty)
        #expect(work.participants?.count == 1)
        #expect(work.participants?.first?.work?.id == work.id)
        #expect(work.checkIns?.count == 1)
        #expect(work.checkIns?.first?.workID == work.id.uuidString)
        #expect(work.steps?.count == 1)
        #expect(work.steps?.first?.work?.id == work.id)
        #expect(work.unifiedNotes?.count == 1)
        #expect(work.unifiedNotes?.first?.work?.id == work.id)
    }

    @Test("deduplicateNotesStrong merges fields and student links")
    func deduplicateNotesStrongMergesFieldsAndStudentLinks() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.allModels)
        let builder = TestEntityBuilder(context: context)

        let student = try builder.buildStudent(firstName: "Alice", lastName: "Smith")

        let sharedID = UUID()
        let noteA = Note(id: sharedID, body: "Body", scope: .all)
        let noteB = Note(id: sharedID, body: "", scope: .students([student.id]), reportedBy: "assistant")

        context.insert(noteA)
        context.insert(noteB)
        noteB.syncStudentLinks(in: context)
        try context.save()

        let deletedCount = DataCleanupService.deduplicateNotesStrong(using: context)
        #expect(deletedCount == 1)

        let remaining = context.safeFetch(FetchDescriptor<Note>())
        TestPatterns.expectCount(remaining, equals: 1)

        let note = remaining[0]
        #expect(note.body == "Body")
        #expect(note.reportedBy == "assistant")

        let links = context.safeFetch(FetchDescriptor<NoteStudentLink>())
        TestPatterns.expectCount(links, equals: 1)
        #expect(links.first?.note?.id == note.id)
        #expect(links.first?.noteID == note.id.uuidString)
    }
}

// MARK: - Unpresented StudentLesson Deduplication Tests

@Suite("DataCleanupService Unpresented StudentLesson Tests", .serialized)
@MainActor
struct DataCleanupServiceUnpresentedStudentLessonTests {

    private static let models: [any PersistentModel.Type] = [
        Student.self, Lesson.self, StudentLesson.self, LessonPresentation.self, Note.self
    ]

    @Test("deduplicateUnpresentedStudentLessons removes duplicates with same lesson and students")
    func deduplicateUnpresentedRemovesDuplicates() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)

        let lessonID = UUID()
        let studentID = UUID()

        // Create duplicate unscheduled, unpresented StudentLessons
        let sl1 = makeTestStudentLesson(lessonID: lessonID, studentIDs: [studentID], scheduledFor: nil, givenAt: nil)
        let sl2 = makeTestStudentLesson(lessonID: lessonID, studentIDs: [studentID], scheduledFor: nil, givenAt: nil)
        context.insert(sl1)
        context.insert(sl2)
        try context.save()

        DataCleanupService.deduplicateUnpresentedStudentLessons(using: context)

        let remaining = context.safeFetch(FetchDescriptor<StudentLesson>())
        TestPatterns.expectCount(remaining, equals: 1)
    }

    @Test("deduplicateUnpresentedStudentLessons preserves scheduled lessons")
    func deduplicateUnpresentedPreservesScheduled() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)

        let lessonID = UUID()
        let studentID = UUID()

        // One scheduled, one unscheduled - should both be preserved
        let sl1 = makeTestStudentLesson(lessonID: lessonID, studentIDs: [studentID], scheduledFor: Date(), givenAt: nil)
        let sl2 = makeTestStudentLesson(lessonID: lessonID, studentIDs: [studentID], scheduledFor: nil, givenAt: nil)
        context.insert(sl1)
        context.insert(sl2)
        try context.save()

        DataCleanupService.deduplicateUnpresentedStudentLessons(using: context)

        let remaining = context.safeFetch(FetchDescriptor<StudentLesson>())
        TestPatterns.expectCount(remaining, equals: 2)
    }

    @Test("deduplicateUnpresentedStudentLessons merges flags to canonical")
    func deduplicateUnpresentedMergesFlags() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)

        let lessonID = UUID()
        let studentID = UUID()

        let oldDate = TestCalendar.date(year: 2025, month: 1, day: 1)
        let newDate = TestCalendar.date(year: 2025, month: 1, day: 15)

        // Older record (will be kept)
        let sl1 = makeTestStudentLesson(lessonID: lessonID, studentIDs: [studentID], scheduledFor: nil, givenAt: nil)
        sl1.createdAt = oldDate
        sl1.needsPractice = false

        // Newer record with needsPractice (will be deleted, but flag merged)
        let sl2 = makeTestStudentLesson(lessonID: lessonID, studentIDs: [studentID], scheduledFor: nil, givenAt: nil)
        sl2.createdAt = newDate
        sl2.needsPractice = true

        context.insert(sl1)
        context.insert(sl2)
        try context.save()

        DataCleanupService.deduplicateUnpresentedStudentLessons(using: context)

        let remaining = context.safeFetch(FetchDescriptor<StudentLesson>())
        TestPatterns.expectCount(remaining, equals: 1)
        #expect(remaining[0].needsPractice == true)
    }
}

// MARK: - Denormalized Field Repair Tests

@Suite("DataCleanupService Denormalized Field Repair Tests", .serialized)
@MainActor
struct DataCleanupServiceDenormalizedFieldRepairTests {

    private static let models: [any PersistentModel.Type] = [
        Student.self, Lesson.self, StudentLesson.self, LessonPresentation.self, Note.self
    ]

    @Test("repairDenormalizedScheduledForDay fixes mismatched dates")
    func repairDenormalizedScheduledForDayFixesMismatched() async throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)

        let scheduledDate = TestCalendar.date(year: 2025, month: 2, day: 15)
        let wrongDayValue = TestCalendar.startOfDay(year: 2025, month: 1, day: 1) // Intentionally wrong

        let sl = makeTestStudentLesson(scheduledFor: scheduledDate)
        sl.scheduledForDay = wrongDayValue // Mismatch
        context.insert(sl)
        try context.save()

        await DataCleanupService.repairDenormalizedScheduledForDay(using: context)

        // scheduledForDay should now match scheduledFor
        let expectedDay = AppCalendar.startOfDay(scheduledDate)
        #expect(sl.scheduledForDay == expectedDay)
    }

    @Test("repairDenormalizedScheduledForDay handles nil scheduledFor")
    func repairDenormalizedScheduledForDayHandlesNil() async throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)

        let sl = makeTestStudentLesson(scheduledFor: nil)
        context.insert(sl)
        try context.save()

        await DataCleanupService.repairDenormalizedScheduledForDay(using: context)

        #expect(sl.scheduledForDay == Date.distantPast)
    }

    @Test("repairDenormalizedScheduledForDay is idempotent")
    func repairDenormalizedScheduledForDayIsIdempotent() async throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)

        let scheduledDate = TestCalendar.date(year: 2025, month: 2, day: 15)
        let sl = makeTestStudentLesson(scheduledFor: scheduledDate)
        context.insert(sl)
        try context.save()

        await DataCleanupService.repairDenormalizedScheduledForDay(using: context)
        let firstResult = sl.scheduledForDay

        await DataCleanupService.repairDenormalizedScheduledForDay(using: context)
        let secondResult = sl.scheduledForDay

        #expect(firstResult == secondResult)
    }
}

// MARK: - Run All Cleanup Tests

@Suite("DataCleanupService Run All Tests", .serialized)
@MainActor
struct DataCleanupServiceRunAllTests {

    @Test("runAllCleanupOperations completes without error")
    func runAllCleanupOperationsCompletes() async throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: [Student.self, Note.self])
        let builder = TestEntityBuilder(context: context)

        _ = try builder.buildStudent()

        await DataCleanupService.runAllCleanupOperations(using: context)
    }

    @Test("runAllCleanupOperations is safe to run multiple times")
    func runAllCleanupOperationsIsSafeToRepeat() async throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: [Student.self, Note.self])

        await DataCleanupService.runAllCleanupOperations(using: context)
        await DataCleanupService.runAllCleanupOperations(using: context)
        await DataCleanupService.runAllCleanupOperations(using: context)
    }
}

#endif
