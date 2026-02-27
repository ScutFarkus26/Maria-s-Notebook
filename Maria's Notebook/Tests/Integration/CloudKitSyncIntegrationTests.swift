#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Student Merge Edge Cases

@Suite("CloudKit Student Merge Edge Cases", .serialized)
@MainActor
struct CloudKitStudentMergeEdgeCaseTests {

    private static let models: [any PersistentModel.Type] = [
        Student.self, Document.self, Lesson.self, StudentLesson.self,
        LessonPresentation.self, Note.self, NoteStudentLink.self,
        WorkModel.self, WorkParticipantEntity.self, WorkCheckIn.self, WorkStep.self
    ]

    @Test("Student merge unions nextLessons from both copies")
    func studentMergeUnionsNextLessons() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)

        let sharedID = UUID()
        let lessonUUID1 = UUID()
        let lessonUUID2 = UUID()

        let studentA = Student(
            id: sharedID, firstName: "Alice", lastName: "Smith",
            birthday: TestCalendar.date(year: 2015, month: 6, day: 15),
            nextLessons: [lessonUUID1]
        )
        let studentB = Student(
            id: sharedID, firstName: "Alice", lastName: "Smith",
            birthday: TestCalendar.date(year: 2015, month: 6, day: 15),
            nextLessons: [lessonUUID2]
        )

        context.insert(studentA)
        context.insert(studentB)
        try context.save()

        let deletedCount = DataCleanupService.deduplicateStudentsStrong(using: context)
        #expect(deletedCount == 1)

        let remaining = context.safeFetch(FetchDescriptor<Student>())
        TestPatterns.expectCount(remaining, equals: 1)

        let student = remaining[0]
        #expect(student.nextLessons.contains(lessonUUID1.uuidString))
        #expect(student.nextLessons.contains(lessonUUID2.uuidString))
    }

    @Test("Student merge fills manualOrder from non-zero and nickname from non-nil")
    func studentMergeFillsManualOrderAndNickname() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)

        let sharedID = UUID()
        let studentA = Student(
            id: sharedID, firstName: "Alice", lastName: "Smith",
            birthday: TestCalendar.date(year: 2015, month: 6, day: 15),
            nickname: nil,
            manualOrder: 0
        )
        let studentB = Student(
            id: sharedID, firstName: "Alice", lastName: "Smith",
            birthday: TestCalendar.date(year: 2015, month: 6, day: 15),
            nickname: "Ali",
            manualOrder: 5
        )

        context.insert(studentA)
        context.insert(studentB)
        try context.save()

        let deletedCount = DataCleanupService.deduplicateStudentsStrong(using: context)
        #expect(deletedCount == 1)

        let remaining = context.safeFetch(FetchDescriptor<Student>())
        TestPatterns.expectCount(remaining, equals: 1)

        let student = remaining[0]
        #expect(student.nickname == "Ali")
        #expect(student.manualOrder == 5)
    }
}

// MARK: - WorkModel Merge Edge Cases

@Suite("CloudKit WorkModel Merge Edge Cases", .serialized)
@MainActor
struct CloudKitWorkModelMergeEdgeCaseTests {

    private static let models: [any PersistentModel.Type] = [
        Student.self, Document.self, Lesson.self, StudentLesson.self,
        LessonPresentation.self, Note.self, NoteStudentLink.self,
        WorkModel.self, WorkParticipantEntity.self, WorkCheckIn.self, WorkStep.self
    ]

    @Test("WorkModel merge fills optional fields from duplicate")
    func workModelMergeFillsOptionalFields() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)

        let sharedID = UUID()
        let dueDate = TestCalendar.date(year: 2025, month: 3, day: 15)
        let studentUUID = UUID()
        let lessonUUID = UUID()

        let workA = WorkModel(
            id: sharedID,
            title: "Work A",
            studentID: "",
            lessonID: "",
            presentationID: nil,
            trackID: nil,
            trackStepID: nil
        )
        let workB = WorkModel(
            id: sharedID,
            title: "",
            dueAt: dueDate,
            studentID: studentUUID.uuidString,
            lessonID: lessonUUID.uuidString,
            presentationID: "P1",
            trackID: "T1",
            trackStepID: "TS1",
            sourceContextType: .projectSession,
            sourceContextID: "SC1"
        )

        context.insert(workA)
        context.insert(workB)
        try context.save()

        let deletedCount = DataCleanupService.deduplicateWorkModelsStrong(using: context)
        #expect(deletedCount == 1)

        let remaining = context.safeFetch(FetchDescriptor<WorkModel>())
        TestPatterns.expectCount(remaining, equals: 1)

        let work = remaining[0]
        #expect(work.title == "Work A")
        #expect(work.dueAt == dueDate)
        #expect(work.studentID == studentUUID.uuidString)
        #expect(work.lessonID == lessonUUID.uuidString)
        #expect(work.presentationID == "P1")
        #expect(work.trackID == "T1")
        #expect(work.trackStepID == "TS1")
        #expect(work.sourceContextTypeRaw == WorkSourceContextType.projectSession.rawValue)
        #expect(work.sourceContextID == "SC1")
    }
}

// MARK: - Note Merge Edge Cases

@Suite("CloudKit Note Merge Edge Cases", .serialized)
@MainActor
struct CloudKitNoteMergeEdgeCaseTests {

    private static let models: [any PersistentModel.Type] = [
        Student.self, Document.self, Lesson.self, StudentLesson.self,
        LessonPresentation.self, Note.self, NoteStudentLink.self,
        WorkModel.self, WorkParticipantEntity.self, WorkCheckIn.self, WorkStep.self
    ]

    @Test("Note merge uses OR logic for boolean flags")
    func noteMergeBooleanFlagsUseOrLogic() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)

        let sharedID = UUID()
        let noteA = Note(id: sharedID, body: "Observation", scope: .all)
        noteA.isPinned = false
        noteA.includeInReport = false

        let noteB = Note(id: sharedID, body: "", scope: .all)
        noteB.isPinned = true
        noteB.includeInReport = true

        context.insert(noteA)
        context.insert(noteB)
        try context.save()

        let deletedCount = DataCleanupService.deduplicateNotesStrong(using: context)
        #expect(deletedCount == 1)

        let remaining = context.safeFetch(FetchDescriptor<Note>())
        TestPatterns.expectCount(remaining, equals: 1)

        let note = remaining[0]
        #expect(note.body == "Observation")
        #expect(note.isPinned == true)
        #expect(note.includeInReport == true)
    }

    @Test("Note merge fills parent relationships from duplicate")
    func noteMergeFillsParentRelationships() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)

        let lesson = Lesson(name: "Intro", subject: "Math", group: "A")
        context.insert(lesson)

        let work = WorkModel(title: "Practice")
        context.insert(work)

        let sharedID = UUID()
        let noteA = Note(id: sharedID, body: "Body", scope: .all, work: work)
        let noteB = Note(id: sharedID, body: "", scope: .all, lesson: lesson)

        context.insert(noteA)
        context.insert(noteB)
        try context.save()

        let deletedCount = DataCleanupService.deduplicateNotesStrong(using: context)
        #expect(deletedCount == 1)

        let remaining = context.safeFetch(FetchDescriptor<Note>())
        TestPatterns.expectCount(remaining, equals: 1)

        let note = remaining[0]
        #expect(note.body == "Body")
        #expect(note.work?.id == work.id)
        #expect(note.lesson?.id == lesson.id)
    }
}

// MARK: - Batch Deduplication

@Suite("CloudKit Batch Deduplication Tests", .serialized)
@MainActor
struct CloudKitBatchDeduplicationTests {

    @Test("deduplicateAllModels removes duplicates across multiple model types")
    func deduplicateAllModelsRemovesAcrossTypes() throws {
        let config = ModelConfiguration(schema: AppSchema.schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: AppSchema.schema, configurations: [config])
        let context = ModelContext(container)

        // Insert duplicate students (same UUID)
        let studentID = UUID()
        let studentA = Student(id: studentID, firstName: "Alice", lastName: "Smith",
                               birthday: TestCalendar.date(year: 2015, month: 6, day: 15))
        let studentB = Student(id: studentID, firstName: "Alice", lastName: "Smith",
                               birthday: TestCalendar.date(year: 2015, month: 6, day: 15))
        context.insert(studentA)
        context.insert(studentB)

        // Insert duplicate lessons (same UUID)
        let lessonID = UUID()
        let lessonA = Lesson(id: lessonID, name: "Intro", subject: "Math", group: "A")
        let lessonB = Lesson(id: lessonID, name: "Intro", subject: "Math", group: "A")
        context.insert(lessonA)
        context.insert(lessonB)

        // Insert one unique note (no duplicates)
        let note = Note(body: "Unique note", scope: .all)
        context.insert(note)

        try context.save()

        let results = DataCleanupService.deduplicateAllModels(using: context)

        // Verify duplicates were removed
        let studentResult = results["Student"] ?? 0
        let lessonResult = results["Lesson"] ?? 0
        #expect(studentResult > 0)
        #expect(lessonResult > 0)

        // Verify correct counts remain
        let remainingStudents = context.safeFetch(FetchDescriptor<Student>())
        TestPatterns.expectCount(remainingStudents, equals: 1)

        let remainingLessons = context.safeFetch(FetchDescriptor<Lesson>())
        TestPatterns.expectCount(remainingLessons, equals: 1)

        let remainingNotes = context.safeFetch(FetchDescriptor<Note>())
        TestPatterns.expectCount(remainingNotes, equals: 1)
    }
}

// MARK: - Fetch Unique & uniqueByID

@Suite("CloudKit Fetch Unique Tests", .serialized)
@MainActor
struct CloudKitFetchUniqueTests {

    private static let models: [any PersistentModel.Type] = [
        Student.self, Document.self
    ]

    @Test("uniqueByID keeps first occurrence and removes duplicates")
    func uniqueByIDKeepsFirstOccurrence() {
        let sharedID = UUID()
        let studentA = Student(id: sharedID, firstName: "Alice", lastName: "Smith",
                               birthday: TestCalendar.date(year: 2015, month: 6, day: 15))
        let studentB = Student(id: sharedID, firstName: "Bob", lastName: "Jones",
                               birthday: TestCalendar.date(year: 2015, month: 6, day: 15))
        let studentC = Student(firstName: "Charlie", lastName: "Brown",
                               birthday: TestCalendar.date(year: 2016, month: 1, day: 1))

        let result = [studentA, studentB, studentC].uniqueByID

        #expect(result.count == 2)
        #expect(result[0].firstName == "Alice")
        #expect(result[1].firstName == "Charlie")
    }

    @Test("fetchUnique returns deduplicated results from context")
    func fetchUniqueReturnsDeduplicated() throws {
        let (_, context) = try TestContainerFactory.makeContainerWithContext(for: Self.models)

        let sharedID = UUID()
        let studentA = Student(id: sharedID, firstName: "Alice", lastName: "Smith",
                               birthday: TestCalendar.date(year: 2015, month: 6, day: 15))
        let studentB = Student(id: sharedID, firstName: "Alice", lastName: "Smith",
                               birthday: TestCalendar.date(year: 2015, month: 6, day: 15))

        context.insert(studentA)
        context.insert(studentB)
        try context.save()

        let result = try context.fetchUnique(FetchDescriptor<Student>())

        #expect(result.count == 1)
    }
}

#endif
