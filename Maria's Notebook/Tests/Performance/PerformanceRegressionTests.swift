#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - Note Repository Regression Tests

/// Critical regression tests for NoteRepository after performance optimizations.
/// These tests verify that the dual-query pattern in fetchNotesForStudent continues to work.
@Suite("NoteRepository Regression Tests", .serialized)
@MainActor
struct NoteRepositoryRegressionTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            Note.self,
            NoteStudentLink.self,
            WorkModel.self,
            WorkParticipantEntity.self,
        ])
    }

    @Test("Regression: Multi-student scoped notes appear for all linked students")
    func regressionMultiStudentScopedNotes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice")
        let student2 = makeTestStudent(firstName: "Bob")
        let student3 = makeTestStudent(firstName: "Charlie")
        context.insert(student1)
        context.insert(student2)
        context.insert(student3)

        // Create note scoped to student1 and student2 (not student3)
        let note = Note(body: "Shared note", scope: .students([student1.id, student2.id]))
        context.insert(note)
        note.syncStudentLinks(in: context)
        try context.save()

        let repository = NoteRepository(context: context)

        // Student 1 should see the note
        let notes1 = repository.fetchNotesForStudent(studentID: student1.id)
        #expect(notes1.count == 1)
        #expect(notes1.first?.body == "Shared note")

        // Student 2 should see the note
        let notes2 = repository.fetchNotesForStudent(studentID: student2.id)
        #expect(notes2.count == 1)
        #expect(notes2.first?.body == "Shared note")

        // Student 3 should NOT see the note
        let notes3 = repository.fetchNotesForStudent(studentID: student3.id)
        #expect(notes3.isEmpty)
    }

    @Test("Regression: Notes with all scope appear for every student")
    func regressionAllScopedNotes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let students = (0..<5).map { i in
            makeTestStudent(firstName: "Student\(i)")
        }
        for student in students {
            context.insert(student)
        }

        let allNote = Note(body: "Note for everyone", scope: .all)
        context.insert(allNote)
        try context.save()

        let repository = NoteRepository(context: context)

        // Every student should see the note
        for student in students {
            let notes = repository.fetchNotesForStudent(studentID: student.id)
            #expect(notes.count == 1)
            #expect(notes.first?.body == "Note for everyone")
        }
    }

    @Test("Regression: Single-student scoped notes only appear for that student")
    func regressionSingleStudentScopedNotes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let targetStudent = makeTestStudent(firstName: "Target")
        let otherStudent = makeTestStudent(firstName: "Other")
        context.insert(targetStudent)
        context.insert(otherStudent)

        let note = Note(body: "Private note", scope: .student(targetStudent.id))
        context.insert(note)
        try context.save()

        let repository = NoteRepository(context: context)

        // Target student should see the note
        let targetNotes = repository.fetchNotesForStudent(studentID: targetStudent.id)
        #expect(targetNotes.count == 1)

        // Other student should NOT see the note
        let otherNotes = repository.fetchNotesForStudent(studentID: otherStudent.id)
        #expect(otherNotes.isEmpty)
    }

    @Test("Regression: Combined scopes work together correctly")
    func regressionCombinedScopes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice")
        let student2 = makeTestStudent(firstName: "Bob")
        context.insert(student1)
        context.insert(student2)

        // Create various notes
        let allNote = Note(body: "All note", scope: .all)
        let student1Note = Note(body: "Alice only", scope: .student(student1.id))
        let sharedNote = Note(body: "Shared", scope: .students([student1.id, student2.id]))

        context.insert(allNote)
        context.insert(student1Note)
        context.insert(sharedNote)
        sharedNote.syncStudentLinks(in: context)
        try context.save()

        let repository = NoteRepository(context: context)

        // Alice should see: all note + her private note + shared note = 3
        let aliceNotes = repository.fetchNotesForStudent(studentID: student1.id)
        #expect(aliceNotes.count == 3)

        // Bob should see: all note + shared note = 2
        let bobNotes = repository.fetchNotesForStudent(studentID: student2.id)
        #expect(bobNotes.count == 2)

        // Verify Bob doesn't see Alice's private note
        let bobBodies = Set(bobNotes.map { $0.body })
        #expect(!bobBodies.contains("Alice only"))
    }
}

// MARK: - GroupTrack Service Regression Tests

/// Critical regression tests for GroupTrackService after performance optimizations.
@Suite("GroupTrackService Regression Tests", .serialized)
@MainActor
struct GroupTrackServiceRegressionTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            GroupTrack.self,
            StudentTrackEnrollment.self,
        ])
    }

    @Test("Regression: getOrCreateGroupTrack deduplicates correctly")
    func regressionGetOrCreateDeduplicates() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        // Call getOrCreate multiple times with same subject/group
        let track1 = try GroupTrackService.getOrCreateGroupTrack(
            subject: "Math",
            group: "Operations",
            modelContext: context
        )

        let track2 = try GroupTrackService.getOrCreateGroupTrack(
            subject: "Math",
            group: "Operations",
            modelContext: context
        )

        let track3 = try GroupTrackService.getOrCreateGroupTrack(
            subject: "math", // lowercase
            group: "OPERATIONS", // uppercase
            modelContext: context
        )

        // All should be the same track
        #expect(track1.id == track2.id)
        #expect(track2.id == track3.id)

        // Should only have one track in database
        let descriptor = FetchDescriptor<GroupTrack>()
        let allTracks = try context.fetch(descriptor)
        #expect(allTracks.count == 1)
    }

    @Test("Regression: Different subjects create different tracks")
    func regressionDifferentSubjectsCreateDifferentTracks() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let mathTrack = try GroupTrackService.getOrCreateGroupTrack(
            subject: "Math",
            group: "Operations",
            modelContext: context
        )

        let langTrack = try GroupTrackService.getOrCreateGroupTrack(
            subject: "Language",
            group: "Operations",
            modelContext: context
        )

        #expect(mathTrack.id != langTrack.id)
        #expect(mathTrack.subject == "Math")
        #expect(langTrack.subject == "Language")
    }

    @Test("Regression: Different groups create different tracks")
    func regressionDifferentGroupsCreateDifferentTracks() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let opsTrack = try GroupTrackService.getOrCreateGroupTrack(
            subject: "Math",
            group: "Operations",
            modelContext: context
        )

        let geoTrack = try GroupTrackService.getOrCreateGroupTrack(
            subject: "Math",
            group: "Geometry",
            modelContext: context
        )

        #expect(opsTrack.id != geoTrack.id)
        #expect(opsTrack.group == "Operations")
        #expect(geoTrack.group == "Geometry")
    }
}

// MARK: - DataQueryService Regression Tests

/// Critical regression tests for DataQueryService after performance optimizations.
@Suite("DataQueryService Regression Tests", .serialized)
@MainActor
struct DataQueryServiceRegressionTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            WorkPlanItem.self,
        ])
    }

    @Test("Regression: fetchStudentLessons returns correct lessons")
    func regressionFetchStudentLessons() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = makeTestStudent(firstName: "Alice")
        let student2 = makeTestStudent(firstName: "Bob")
        let lesson1 = makeTestLesson(name: "Lesson 1")
        let lesson2 = makeTestLesson(name: "Lesson 2")
        let lesson3 = makeTestLesson(name: "Lesson 3")

        context.insert(student1)
        context.insert(student2)
        context.insert(lesson1)
        context.insert(lesson2)
        context.insert(lesson3)

        // Alice gets lesson 1 and 2
        let sl1 = StudentLesson(lesson: lesson1, students: [student1])
        let sl2 = StudentLesson(lesson: lesson2, students: [student1])

        // Bob gets lesson 3
        let sl3 = StudentLesson(lesson: lesson3, students: [student2])

        // Shared lesson for both
        let sl4 = StudentLesson(lesson: lesson1, students: [student1, student2])

        context.insert(sl1)
        context.insert(sl2)
        context.insert(sl3)
        context.insert(sl4)
        try context.save()

        let service = DataQueryService(context: context)

        // Alice should see: sl1, sl2, sl4 (3 student lessons)
        let aliceLessons = service.fetchStudentLessons(for: student1.id)
        #expect(aliceLessons.count == 3)

        // Bob should see: sl3, sl4 (2 student lessons)
        let bobLessons = service.fetchStudentLessons(for: student2.id)
        #expect(bobLessons.count == 2)
    }

    @Test("Regression: fetchOpenWorkModels returns active and review only")
    func regressionFetchOpenWorkModels() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let activeWork = makeTestWorkModel(title: "Active", status: .active)
        let reviewWork = makeTestWorkModel(title: "Review", status: .review)
        let completedWork = makeTestWorkModel(title: "Completed", status: .complete)

        context.insert(activeWork)
        context.insert(reviewWork)
        context.insert(completedWork)
        try context.save()

        let service = DataQueryService(context: context)
        let openWork = service.fetchOpenWorkModels()

        #expect(openWork.count == 2)

        let titles = Set(openWork.map { $0.title })
        #expect(titles.contains("Active"))
        #expect(titles.contains("Review"))
        #expect(!titles.contains("Completed"))
    }
}

// MARK: - NoteStudentLink Regression Tests

/// Critical regression tests for NoteStudentLink sync behavior.
@Suite("NoteStudentLink Regression Tests", .serialized)
@MainActor
struct NoteStudentLinkRegressionTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Note.self,
            NoteStudentLink.self,
        ])
    }

    @Test("Regression: Links are created for multi-student scope")
    func regressionLinksCreatedForMultiStudent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentIDs = [UUID(), UUID(), UUID()]
        let note = Note(body: "Multi note", scope: .students(studentIDs))
        context.insert(note)
        note.syncStudentLinks(in: context)
        try context.save()

        let noteIDString = note.id.uuidString
        let descriptor = FetchDescriptor<NoteStudentLink>(
            predicate: #Predicate<NoteStudentLink> { $0.noteID == noteIDString }
        )
        let links = try context.fetch(descriptor)

        #expect(links.count == 3)

        let linkedStudentIDs = Set(links.map { $0.studentID })
        for studentID in studentIDs {
            #expect(linkedStudentIDs.contains(studentID.uuidString))
        }
    }

    @Test("Regression: Links are removed when scope changes")
    func regressionLinksRemovedOnScopeChange() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentIDs = [UUID(), UUID()]
        let note = Note(body: "Note", scope: .students(studentIDs))
        context.insert(note)
        note.syncStudentLinks(in: context)
        try context.save()

        // Verify links exist
        let noteIDString = note.id.uuidString
        var descriptor = FetchDescriptor<NoteStudentLink>(
            predicate: #Predicate<NoteStudentLink> { $0.noteID == noteIDString }
        )
        var links = try context.fetch(descriptor)
        #expect(links.count == 2)

        // Change to all scope
        note.scope = .all
        note.syncStudentLinks(in: context)
        try context.save()

        // Links should be removed
        descriptor = FetchDescriptor<NoteStudentLink>(
            predicate: #Predicate<NoteStudentLink> { $0.noteID == noteIDString }
        )
        links = try context.fetch(descriptor)
        #expect(links.isEmpty)
    }

    @Test("Regression: Links update when students change")
    func regressionLinksUpdateOnStudentChange() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let student1 = UUID()
        let student2 = UUID()
        let student3 = UUID()

        let note = Note(body: "Note", scope: .students([student1, student2]))
        context.insert(note)
        note.syncStudentLinks(in: context)
        try context.save()

        // Change students
        note.scope = .students([student2, student3])
        note.syncStudentLinks(in: context)
        try context.save()

        let noteIDString = note.id.uuidString
        let descriptor = FetchDescriptor<NoteStudentLink>(
            predicate: #Predicate<NoteStudentLink> { $0.noteID == noteIDString }
        )
        let links = try context.fetch(descriptor)

        #expect(links.count == 2)

        let linkedStudentIDs = Set(links.map { $0.studentID })
        #expect(!linkedStudentIDs.contains(student1.uuidString)) // Removed
        #expect(linkedStudentIDs.contains(student2.uuidString))  // Kept
        #expect(linkedStudentIDs.contains(student3.uuidString))  // Added
    }
}

// MARK: - Index Regression Tests

/// Tests to ensure indexed field queries work correctly after adding @Index.
@Suite("Index Regression Tests", .serialized)
@MainActor
struct IndexRegressionTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Note.self,
            NoteStudentLink.self,
            StudentTrackEnrollment.self,
            GroupTrack.self,
        ])
    }

    @Test("Regression: searchIndexStudentID queries return correct results")
    func regressionSearchIndexStudentIDQuery() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let otherStudentID = UUID()

        let note1 = Note(body: "Note 1", scope: .student(studentID))
        let note2 = Note(body: "Note 2", scope: .student(otherStudentID))
        let note3 = Note(body: "Note 3", scope: .student(studentID))

        context.insert(note1)
        context.insert(note2)
        context.insert(note3)
        try context.save()

        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.searchIndexStudentID == studentID }
        )
        let results = try context.fetch(descriptor)

        #expect(results.count == 2)

        let bodies = Set(results.map { $0.body })
        #expect(bodies.contains("Note 1"))
        #expect(bodies.contains("Note 3"))
        #expect(!bodies.contains("Note 2"))
    }

    @Test("Regression: scopeIsAll queries return correct results")
    func regressionScopeIsAllQuery() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let note1 = Note(body: "All note 1", scope: .all)
        let note2 = Note(body: "Student note", scope: .student(UUID()))
        let note3 = Note(body: "All note 2", scope: .all)

        context.insert(note1)
        context.insert(note2)
        context.insert(note3)
        try context.save()

        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> { $0.scopeIsAll == true }
        )
        let results = try context.fetch(descriptor)

        #expect(results.count == 2)

        let bodies = Set(results.map { $0.body })
        #expect(bodies.contains("All note 1"))
        #expect(bodies.contains("All note 2"))
        #expect(!bodies.contains("Student note"))
    }

    @Test("Regression: Combined index queries work correctly")
    func regressionCombinedIndexQuery() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()

        // Various notes
        let allNote = Note(body: "All", scope: .all)
        let studentNote = Note(body: "Student", scope: .student(studentID))
        let otherNote = Note(body: "Other", scope: .student(UUID()))

        context.insert(allNote)
        context.insert(studentNote)
        context.insert(otherNote)
        try context.save()

        // Query for notes visible to studentID (all OR specific student)
        let descriptor = FetchDescriptor<Note>(
            predicate: #Predicate<Note> {
                $0.scopeIsAll == true || $0.searchIndexStudentID == studentID
            }
        )
        let results = try context.fetch(descriptor)

        #expect(results.count == 2)

        let bodies = Set(results.map { $0.body })
        #expect(bodies.contains("All"))
        #expect(bodies.contains("Student"))
        #expect(!bodies.contains("Other"))
    }
}

// MARK: - Scope Decoding Regression Tests

/// Tests to ensure scope encoding/decoding remains stable.
@Suite("Scope Encoding Regression Tests", .serialized)
@MainActor
struct ScopeEncodingRegressionTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [Note.self, NoteStudentLink.self])
    }

    @Test("Regression: All scope encodes and decodes correctly")
    func regressionAllScopeEncoding() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let note = Note(body: "Test", scope: .all)
        context.insert(note)
        try context.save()

        // Re-fetch and verify
        let descriptor = FetchDescriptor<Note>()
        let fetched = try context.fetch(descriptor).first!

        if case .all = fetched.scope {
            // Success
        } else {
            Issue.record("Expected .all scope")
        }
    }

    @Test("Regression: Student scope encodes and decodes correctly")
    func regressionStudentScopeEncoding() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let note = Note(body: "Test", scope: .student(studentID))
        context.insert(note)
        try context.save()

        // Re-fetch and verify
        let descriptor = FetchDescriptor<Note>()
        let fetched = try context.fetch(descriptor).first!

        if case .student(let id) = fetched.scope {
            #expect(id == studentID)
        } else {
            Issue.record("Expected .student scope")
        }
    }

    @Test("Regression: Students scope encodes and decodes correctly")
    func regressionStudentsScopeEncoding() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentIDs = [UUID(), UUID(), UUID()]
        let note = Note(body: "Test", scope: .students(studentIDs))
        context.insert(note)
        note.syncStudentLinks(in: context)
        try context.save()

        // Re-fetch and verify
        let descriptor = FetchDescriptor<Note>()
        let fetched = try context.fetch(descriptor).first!

        if case .students(let ids) = fetched.scope {
            #expect(Set(ids) == Set(studentIDs))
        } else {
            Issue.record("Expected .students scope")
        }
    }
}

#endif
