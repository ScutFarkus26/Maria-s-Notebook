#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Shared Test Helpers

/// Common container configurations for performance tests
private enum TestContainers {
    static let noteQueryTypes: [any PersistentModel.Type] = [
        Student.self, Lesson.self, StudentLesson.self, Note.self,
        NoteStudentLink.self, WorkModel.self, WorkParticipantEntity.self
    ]
    
    static let studentLessonTypes: [any PersistentModel.Type] = [
        Student.self, Lesson.self, StudentLesson.self, Note.self,
        NoteStudentLink.self, WorkModel.self, WorkParticipantEntity.self,
        LessonPresentation.self
    ]
    
    static let groupTrackTypes: [any PersistentModel.Type] = [
        Student.self, Lesson.self, StudentLesson.self,
        GroupTrack.self, StudentTrackEnrollment.self
    ]
    
    static let workQueryTypes: [any PersistentModel.Type] = [
        Student.self, Lesson.self, WorkModel.self,
        WorkParticipantEntity.self, WorkCheckIn.self
    ]
    
    static let indexTestTypes: [any PersistentModel.Type] = [
        Student.self, Note.self, NoteStudentLink.self,
        StudentTrackEnrollment.self, GroupTrack.self
    ]
    
    static let batchOperationTypes: [any PersistentModel.Type] = [
        Student.self, Note.self, NoteStudentLink.self
    ]
    
    static let deduplicationTypes: [any PersistentModel.Type] = [
        Student.self, Lesson.self, StudentLesson.self
    ]
}

// MARK: - Note Query Performance Tests

/// Tests to ensure note fetching behavior remains correct during performance optimizations.
/// These tests verify the current behavior so we know if optimizations break anything.
@Suite("Note Query Behavior Tests", .serialized)
@MainActor
struct NoteQueryBehaviorTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: TestContainers.noteQueryTypes)
    }

    @Test("fetchNotesForStudent returns notes with all scope")
    func fetchNotesForStudentReturnsAllScopedNotes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()

        // Create note with .all scope
        let allNote = Note(body: "Note for everyone", scope: .all)
        context.insert(allNote)
        try context.save()

        let repository = NoteRepository(context: context)
        let fetched = repository.fetchNotesForStudent(studentID: studentID)

        #expect(fetched.count == 1)
        #expect(fetched.first?.body == "Note for everyone")
    }

    @Test("fetchNotesForStudent returns notes with matching student scope")
    func fetchNotesForStudentReturnsMatchingStudentScope() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let otherStudentID = UUID()

        // Create notes for different students
        let myNote = Note(body: "My note", scope: .student(studentID))
        let otherNote = Note(body: "Other note", scope: .student(otherStudentID))
        context.insert(myNote)
        context.insert(otherNote)
        try context.save()

        let repository = NoteRepository(context: context)
        let fetched = repository.fetchNotesForStudent(studentID: studentID)

        #expect(fetched.count == 1)
        #expect(fetched.first?.body == "My note")
    }

    @Test("fetchNotesForStudent returns notes linked via NoteStudentLink")
    func fetchNotesForStudentReturnsLinkedNotes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID1 = UUID()
        let studentID2 = UUID()

        // Create note with multi-student scope
        let multiNote = Note(body: "Multi-student note", scope: .students([studentID1, studentID2]))
        context.insert(multiNote)
        multiNote.syncStudentLinks(in: context)
        try context.save()

        let repository = NoteRepository(context: context)

        // Both students should see this note
        let fetched1 = repository.fetchNotesForStudent(studentID: studentID1)
        let fetched2 = repository.fetchNotesForStudent(studentID: studentID2)

        #expect(fetched1.count == 1)
        #expect(fetched2.count == 1)
        #expect(fetched1.first?.body == "Multi-student note")
        #expect(fetched2.first?.body == "Multi-student note")
    }

    @Test("fetchNotesForStudent excludes unrelated notes")
    func fetchNotesForStudentExcludesUnrelatedNotes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let myStudentID = UUID()
        let otherStudentID = UUID()

        // Create various notes
        let myNote = Note(body: "My note", scope: .student(myStudentID))
        let otherNote = Note(body: "Other student note", scope: .student(otherStudentID))
        let allNote = Note(body: "All note", scope: .all)

        context.insert(myNote)
        context.insert(otherNote)
        context.insert(allNote)
        try context.save()

        let repository = NoteRepository(context: context)
        let fetched = repository.fetchNotesForStudent(studentID: myStudentID)

        // Should get my note and all note, but not other student's note
        #expect(fetched.count == 2)
        let bodies = Set(fetched.map { $0.body })
        #expect(bodies.contains("My note"))
        #expect(bodies.contains("All note"))
        #expect(!bodies.contains("Other student note"))
    }

    @Test("fetchNotesForStudent handles larger dataset correctly")
    func fetchNotesForStudentHandlesLargeDataset() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let targetStudentID = UUID()
        let otherStudentIDs = (0..<5).map { _ in UUID() }

        // Create 20 notes for target student
        for i in 0..<20 {
            let note = Note(body: "Target note \(i)", scope: .student(targetStudentID))
            context.insert(note)
        }

        // Create 30 notes for other students
        for i in 0..<30 {
            let otherID = otherStudentIDs[i % otherStudentIDs.count]
            let note = Note(body: "Other note \(i)", scope: .student(otherID))
            context.insert(note)
        }

        // Create 10 notes with all scope
        for i in 0..<10 {
            let note = Note(body: "All note \(i)", scope: .all)
            context.insert(note)
        }

        try context.save()

        let repository = NoteRepository(context: context)
        let fetched = repository.fetchNotesForStudent(studentID: targetStudentID)

        // Should get 20 targeted + 10 all-scoped = 30 notes
        #expect(fetched.count == 30)
    }
}

// MARK: - StudentLesson Query Behavior Tests

@Suite("StudentLesson Query Behavior Tests", .serialized)
@MainActor
struct StudentLessonQueryBehaviorTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: TestContainers.studentLessonTypes)
    }

    @Test("fetchStudentLessons returns lessons for specific student")
    func fetchStudentLessonsReturnsForStudent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student = makeTestStudent(firstName: "Test", lastName: "Student")
        let lesson = makeTestLesson(name: "Math Lesson")
        context.insert(student)
        context.insert(lesson)

        let studentLesson = StudentLesson(
            lesson: lesson,
            students: [student],
            scheduledFor: Date(),
            givenAt: nil,
            isPresented: false
        )
        context.insert(studentLesson)
        try context.save()

        let service = DataQueryService(context: context)
        let fetched = service.fetchStudentLessons(for: student.id)

        #expect(fetched.count == 1)
        #expect(fetched.first?.lessonID == lesson.id.uuidString)
    }

    @Test("fetchStudentLessons excludes lessons for other students")
    func fetchStudentLessonsExcludesOtherStudents() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Student", lastName: "One")
        let student2 = makeTestStudent(firstName: "Student", lastName: "Two")
        let lesson1 = makeTestLesson(name: "Lesson One")
        let lesson2 = makeTestLesson(name: "Lesson Two")
        context.insert(student1)
        context.insert(student2)
        context.insert(lesson1)
        context.insert(lesson2)

        let sl1 = StudentLesson(lesson: lesson1, students: [student1])
        let sl2 = StudentLesson(lesson: lesson2, students: [student2])
        context.insert(sl1)
        context.insert(sl2)
        try context.save()

        let service = DataQueryService(context: context)
        let fetched = service.fetchStudentLessons(for: student1.id)

        #expect(fetched.count == 1)
        #expect(fetched.first?.lessonID == lesson1.id.uuidString)
    }

    @Test("fetchStudentLessons returns lessons with multiple students including target")
    func fetchStudentLessonsReturnsMultiStudentLessons() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Student", lastName: "One")
        let student2 = makeTestStudent(firstName: "Student", lastName: "Two")
        let lesson = makeTestLesson(name: "Group Lesson")
        context.insert(student1)
        context.insert(student2)
        context.insert(lesson)

        let groupLesson = StudentLesson(lesson: lesson, students: [student1, student2])
        context.insert(groupLesson)
        try context.save()

        let service = DataQueryService(context: context)

        // Both students should see the group lesson
        let fetched1 = service.fetchStudentLessons(for: student1.id)
        let fetched2 = service.fetchStudentLessons(for: student2.id)

        #expect(fetched1.count == 1)
        #expect(fetched2.count == 1)
    }
}

// MARK: - GroupTrack Query Behavior Tests

@Suite("GroupTrack Query Behavior Tests", .serialized)
@MainActor
struct GroupTrackQueryBehaviorTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: TestContainers.groupTrackTypes)
    }

    @Test("getOrCreateGroupTrack returns existing track")
    func getOrCreateReturnsExistingTrack() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create existing track
        let existingTrack = GroupTrack(subject: "Math", group: "Operations")
        context.insert(existingTrack)
        try context.save()

        // Get or create should return existing
        let track = try GroupTrackService.getOrCreateGroupTrack(
            subject: "Math",
            group: "Operations",
            modelContext: context
        )

        #expect(track.id == existingTrack.id)
    }

    @Test("getOrCreateGroupTrack is case insensitive")
    func getOrCreateIsCaseInsensitive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create track with specific casing
        let existingTrack = GroupTrack(subject: "Math", group: "Operations")
        context.insert(existingTrack)
        try context.save()

        // Request with different casing
        let track = try GroupTrackService.getOrCreateGroupTrack(
            subject: "MATH",
            group: "operations",
            modelContext: context
        )

        #expect(track.id == existingTrack.id)
    }

    @Test("getOrCreateGroupTrack trims whitespace")
    func getOrCreateTrimsWhitespace() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create track
        let existingTrack = GroupTrack(subject: "Math", group: "Operations")
        context.insert(existingTrack)
        try context.save()

        // Request with whitespace
        let track = try GroupTrackService.getOrCreateGroupTrack(
            subject: "  Math  ",
            group: "  Operations  ",
            modelContext: context
        )

        #expect(track.id == existingTrack.id)
    }

    @Test("getOrCreateGroupTrack creates new track when not found")
    func getOrCreateCreatesNewTrack() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create track for different subject
        let existingTrack = GroupTrack(subject: "Math", group: "Operations")
        context.insert(existingTrack)
        try context.save()

        // Request different subject
        let track = try GroupTrackService.getOrCreateGroupTrack(
            subject: "Language",
            group: "Reading",
            modelContext: context
        )

        #expect(track.id != existingTrack.id)
        #expect(track.subject == "Language")
        #expect(track.group == "Reading")
    }
}

// MARK: - Work Query Behavior Tests

@Suite("Work Query Behavior Tests", .serialized)
@MainActor
struct WorkQueryBehaviorTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: TestContainers.workQueryTypes)
    }

    @Test("fetchOpenWorkModels returns active work")
    func fetchOpenWorkModelsReturnsActive() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let activeWork = makeTestWorkModel(title: "Active Work", status: .active)
        let completedWork = makeTestWorkModel(title: "Completed Work", status: .complete)
        context.insert(activeWork)
        context.insert(completedWork)
        try context.save()

        let service = DataQueryService(context: context)
        let fetched = service.fetchOpenWorkModels()

        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Active Work")
    }

    @Test("fetchOpenWorkModels returns review work")
    func fetchOpenWorkModelsReturnsReview() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let reviewWork = makeTestWorkModel(title: "Review Work", status: .review)
        let completedWork = makeTestWorkModel(title: "Completed Work", status: .complete)
        context.insert(reviewWork)
        context.insert(completedWork)
        try context.save()

        let service = DataQueryService(context: context)
        let fetched = service.fetchOpenWorkModels()

        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Review Work")
    }

    @Test("fetchOpenWorkModels excludes completed work")
    func fetchOpenWorkModelsExcludesCompleted() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let completedWork = makeTestWorkModel(title: "Completed Work", status: .complete)
        context.insert(completedWork)
        try context.save()

        let service = DataQueryService(context: context)
        let fetched = service.fetchOpenWorkModels()

        #expect(fetched.isEmpty)
    }
}

// MARK: - Index Verification Tests

/// These tests verify that queries using indexed fields work correctly.
/// After adding @Index annotations, these ensure the behavior is unchanged.
@Suite("Index Field Behavior Tests", .serialized)
@MainActor
struct IndexFieldBehaviorTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: TestContainers.indexTestTypes)
    }

    @Test("Note searchIndexStudentID filtering works correctly")
    func noteSearchIndexStudentIDFiltering() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()

        // Create note with student scope (which sets searchIndexStudentID)
        let note = Note(body: "Student note", scope: .student(studentID))
        context.insert(note)
        try context.save()

        // Verify searchIndexStudentID is set correctly
        #expect(note.searchIndexStudentID == studentID)

        // Query using searchIndexStudentID
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.searchIndexStudentID == studentID }
        )
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched.first?.body == "Student note")
    }

    @Test("Note scopeIsAll filtering works correctly")
    func noteScopeIsAllFiltering() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create notes with different scopes
        let allNote = Note(body: "All note", scope: .all)
        let studentNote = Note(body: "Student note", scope: .student(UUID()))
        context.insert(allNote)
        context.insert(studentNote)
        try context.save()

        // Query using scopeIsAll
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.scopeIsAll == true }
        )
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched.first?.body == "All note")
    }

    @Test("StudentTrackEnrollment studentID filtering works correctly")
    func enrollmentStudentIDFiltering() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let track = makeTestGroupTrack(subject: "Math", group: "Operations")
        context.insert(track)

        let enrollment = StudentTrackEnrollment(
            studentID: studentID.uuidString,
            trackID: track.id.uuidString
        )
        context.insert(enrollment)
        try context.save()

        // Query using studentID
        let studentIDString = studentID.uuidString
        let descriptor = FetchDescriptor<StudentTrackEnrollment>(
            predicate: #Predicate<StudentTrackEnrollment> { $0.studentID == studentIDString }
        )
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched.first?.studentID == studentIDString)
    }

    @Test("StudentTrackEnrollment trackID filtering works correctly")
    func enrollmentTrackIDFiltering() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let track = makeTestGroupTrack(subject: "Math", group: "Operations")
        context.insert(track)

        let enrollment = StudentTrackEnrollment(
            studentID: UUID().uuidString,
            trackID: track.id.uuidString
        )
        context.insert(enrollment)
        try context.save()

        // Query using trackID
        let trackIDString = track.id.uuidString
        let descriptor = FetchDescriptor<StudentTrackEnrollment>(
            predicate: #Predicate<StudentTrackEnrollment> { $0.trackID == trackIDString }
        )
        let fetched = try context.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched.first?.trackID == trackIDString)
    }
}

// MARK: - Batch Operation Behavior Tests

@Suite("Batch Operation Behavior Tests", .serialized)
@MainActor
struct BatchOperationBehaviorTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: TestContainers.batchOperationTypes)
    }

    @Test("syncStudentLinks creates links for multi-student scope")
    func syncStudentLinksCreatesLinks() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentIDs = [UUID(), UUID(), UUID()]

        let note = Note(body: "Multi-student note", scope: .students(studentIDs))
        context.insert(note)
        note.syncStudentLinks(in: context)
        try context.save()

        // Verify links were created
        let descriptor = FetchDescriptor<NoteStudentLink>()
        let links = try context.fetch(descriptor)

        #expect(links.count == 3)

        let linkedStudentIDs = Set(links.map { $0.studentID })
        for studentID in studentIDs {
            #expect(linkedStudentIDs.contains(studentID.uuidString))
        }
    }

    @Test("syncStudentLinks removes old links when scope changes")
    func syncStudentLinksRemovesOldLinks() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentIDs = [UUID(), UUID(), UUID()]
        let newStudentID = UUID()

        // Create note with multi-student scope
        let note = Note(body: "Multi-student note", scope: .students(studentIDs))
        context.insert(note)
        note.syncStudentLinks(in: context)
        try context.save()

        // Change scope to single student
        note.scope = .student(newStudentID)
        note.syncStudentLinks(in: context)
        try context.save()

        // Verify old links were removed and new link created
        let noteIDString = note.id.uuidString
        let descriptor = FetchDescriptor<NoteStudentLink>(
            predicate: #Predicate<NoteStudentLink> { $0.noteID == noteIDString }
        )
        let links = try context.fetch(descriptor)

        // Single student scope doesn't use links, so should be empty
        #expect(links.isEmpty)
    }

    @Test("syncStudentLinks handles empty student list")
    func syncStudentLinksHandlesEmptyList() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Create note with empty students scope (should become .all)
        let note = Note(body: "Note", scope: .students([]))
        context.insert(note)
        note.syncStudentLinks(in: context)
        try context.save()

        let descriptor = FetchDescriptor<NoteStudentLink>()
        let links = try context.fetch(descriptor)

        #expect(links.isEmpty)
    }
}

// MARK: - Deduplication Behavior Tests

@Suite("Deduplication Behavior Tests", .serialized)
@MainActor
struct DeduplicationBehaviorTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: TestContainers.deduplicationTypes)
    }

    @Test("uniqueByID extension removes duplicates keeping first occurrence")
    func uniqueByIDRemovesDuplicates() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let lesson = makeTestLesson(name: "Test Lesson")
        context.insert(lesson)

        // Create student lessons with same IDs (simulating duplicates)
        let id1 = UUID()
        let id2 = UUID()

        let sl1 = makeTestStudentLesson(id: id1, lessonID: lesson.id)
        let sl2 = makeTestStudentLesson(id: id1, lessonID: lesson.id) // Duplicate of sl1
        let sl3 = makeTestStudentLesson(id: id2, lessonID: lesson.id)

        let array = [sl1, sl2, sl3]
        let unique = array.uniqueByID

        #expect(unique.count == 2)

        let ids = Set(unique.map { $0.id })
        #expect(ids.contains(id1))
        #expect(ids.contains(id2))
    }
}

#endif
