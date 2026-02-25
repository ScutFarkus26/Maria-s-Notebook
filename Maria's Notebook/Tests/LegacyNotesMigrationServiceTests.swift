#if canImport(Testing)
import Testing
import Foundation
import SwiftData
@testable import Maria_s_Notebook

// MARK: - StudentLesson Notes Migration Tests

@Suite("LegacyNotesMigrationService StudentLesson Tests", .serialized)
@MainActor
struct LegacyNotesMigrationServiceStudentLessonTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            Lesson.self,
            StudentLesson.self,
            LessonPresentation.self,
            Note.self,
            NoteStudentLink.self,
        ])
    }

    @Test("migrateStudentLessonNotes creates Note from legacy notes field")
    func migrateStudentLessonNotesCreatesNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sl = makeTestStudentLesson(notes: "Student showed great understanding")
        context.insert(sl)
        try context.save()

        LegacyNotesMigrationService.migrateStudentLessonNotes(using: context)

        // Legacy notes should be cleared
        #expect(sl.notes.isEmpty)

        // A Note should have been created
        let notes = context.safeFetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
        #expect(notes[0].body == "Student showed great understanding")
        #expect(notes[0].studentLesson?.id == sl.id)
    }

    @Test("migrateStudentLessonNotes skips empty notes")
    func migrateStudentLessonNotesSkipsEmpty() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sl = makeTestStudentLesson(notes: "")
        context.insert(sl)
        try context.save()

        LegacyNotesMigrationService.migrateStudentLessonNotes(using: context)

        let notes = context.safeFetch(FetchDescriptor<Note>())
        #expect(notes.isEmpty)
    }

    @Test("migrateStudentLessonNotes skips already migrated")
    func migrateStudentLessonNotesSkipsAlreadyMigrated() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sl = makeTestStudentLesson(notes: "Test note")

        // Pre-add a unified note (simulating already migrated)
        let existingNote = Note(body: "Existing note", scope: .all, studentLesson: sl)
        context.insert(sl)
        context.insert(existingNote)
        sl.unifiedNotes = [existingNote]
        try context.save()

        LegacyNotesMigrationService.migrateStudentLessonNotes(using: context)

        // Should not create additional notes
        let notes = context.safeFetch(FetchDescriptor<Note>())
        #expect(notes.count == 1) // Only the existing one
    }

    @Test("migrateStudentLessonNotes sets scope from studentIDs")
    func migrateStudentLessonNotesSetsScope() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let sl = makeTestStudentLesson(studentIDs: [studentID], notes: "Test note")
        context.insert(sl)
        try context.save()

        LegacyNotesMigrationService.migrateStudentLessonNotes(using: context)

        let notes = context.safeFetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)

        if case .student(let id) = notes[0].scope {
            #expect(id == studentID)
        } else {
            Issue.record("Expected student scope")
        }
    }

    @Test("migrateStudentLessonNotes is idempotent")
    func migrateStudentLessonNotesIsIdempotent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let sl = makeTestStudentLesson(notes: "Test note")
        context.insert(sl)
        try context.save()

        LegacyNotesMigrationService.migrateStudentLessonNotes(using: context)
        LegacyNotesMigrationService.migrateStudentLessonNotes(using: context)

        let notes = context.safeFetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
    }
}

// MARK: - WorkModel Notes Migration Tests

@Suite("LegacyNotesMigrationService WorkModel Tests", .serialized)
@MainActor
struct LegacyNotesMigrationServiceWorkModelTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            WorkModel.self,
            WorkParticipantEntity.self,
            WorkCheckIn.self,
            Note.self,
            NoteStudentLink.self,
        ])
    }

    @Test("migrateWorkNotes creates Note from legacy notes field")
    func migrateWorkNotesCreatesNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = makeTestWorkModel()
        work.notes = "Work in progress, needs more practice"
        context.insert(work)
        try context.save()

        LegacyNotesMigrationService.migrateWorkNotes(using: context)

        // Legacy notes should be cleared
        #expect(work.notes.isEmpty)

        // A Note should have been created
        let notes = context.safeFetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
        #expect(notes[0].body == "Work in progress, needs more practice")
        #expect(notes[0].work?.id == work.id)
    }

    @Test("migrateWorkNotes skips empty notes")
    func migrateWorkNotesSkipsEmpty() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = makeTestWorkModel()
        work.notes = ""
        context.insert(work)
        try context.save()

        LegacyNotesMigrationService.migrateWorkNotes(using: context)

        let notes = context.safeFetch(FetchDescriptor<Note>())
        #expect(notes.isEmpty)
    }

    @Test("migrateWorkNotes is idempotent")
    func migrateWorkNotesIsIdempotent() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let work = makeTestWorkModel()
        work.notes = "Test note"
        context.insert(work)
        try context.save()

        LegacyNotesMigrationService.migrateWorkNotes(using: context)
        LegacyNotesMigrationService.migrateWorkNotes(using: context)

        let notes = context.safeFetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
    }
}

// MARK: - AttendanceRecord Notes Migration Tests

@Suite("LegacyNotesMigrationService AttendanceRecord Tests", .serialized)
@MainActor
struct LegacyNotesMigrationServiceAttendanceRecordTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeTestContainer(for: [
            Student.self,
            AttendanceRecord.self,
            Note.self,
            NoteStudentLink.self,
        ])
    }

    @Test("migrateAttendanceNotes creates Note with attendance category")
    func migrateAttendanceNotesCreatesNote() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let record = makeTestAttendanceRecord(studentID: studentID, note: "Arrived late due to appointment")
        context.insert(record)
        try context.save()

        LegacyNotesMigrationService.migrateAttendanceNotes(using: context)

        // Legacy note should be cleared
        #expect(record.note == nil)

        // A Note should have been created
        let notes = context.safeFetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)
        #expect(notes[0].body == "Arrived late due to appointment")
        #expect(notes[0].tags.contains(TagHelper.tagFromNoteCategory("attendance")))
        #expect(notes[0].attendanceRecord?.id == record.id)
    }

    @Test("migrateAttendanceNotes skips nil notes")
    func migrateAttendanceNotesSkipsNil() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let record = makeTestAttendanceRecord(studentID: studentID, note: nil)
        context.insert(record)
        try context.save()

        LegacyNotesMigrationService.migrateAttendanceNotes(using: context)

        let notes = context.safeFetch(FetchDescriptor<Note>())
        #expect(notes.isEmpty)
    }

    @Test("migrateAttendanceNotes sets scope to student")
    func migrateAttendanceNotesSetsStudentScope() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        let studentID = UUID()
        let record = makeTestAttendanceRecord(studentID: studentID, note: "Test note")
        context.insert(record)
        try context.save()

        LegacyNotesMigrationService.migrateAttendanceNotes(using: context)

        let notes = context.safeFetch(FetchDescriptor<Note>())
        #expect(notes.count == 1)

        if case .student(let id) = notes[0].scope {
            #expect(id == studentID)
        } else {
            Issue.record("Expected student scope")
        }
    }
}

// MARK: - Run All Legacy Notes Migrations Tests

@Suite("LegacyNotesMigrationService Run All Tests", .serialized)
@MainActor
struct LegacyNotesMigrationServiceRunAllTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("runAllLegacyNotesMigrations completes without error")
    func runAllLegacyNotesMigrationsCompletes() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        LegacyNotesMigrationService.runAllLegacyNotesMigrations(using: context)

        // Should complete without error
    }

    @Test("runAllLegacyNotesMigrations is safe to run multiple times")
    func runAllLegacyNotesMigrationsIsSafeToRepeat() throws {
        let container = try makeContainer()
        let context = ModelContext(container)

        LegacyNotesMigrationService.runAllLegacyNotesMigrations(using: context)
        LegacyNotesMigrationService.runAllLegacyNotesMigrations(using: context)

        // Should complete without error
    }
}

#endif
