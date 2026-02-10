//
//  NoteRepository.swift
//  Maria's Notebook
//
//  Repository for Note entity CRUD operations.
//  Follows the pattern established by WorkRepository.
//

import Foundation
import SwiftData

@MainActor
struct NoteRepository: SavingRepository {
    typealias Model = Note

    let context: ModelContext
    let saveCoordinator: SaveCoordinator?

    init(context: ModelContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a Note by ID
    func fetchNote(id: UUID) -> Note? {
        var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
    }

    /// Fetch multiple Notes with optional filtering and sorting
    /// - Parameters:
    ///   - predicate: Optional predicate to filter notes. If nil, fetches all.
    ///   - sortBy: Optional sort descriptors. Defaults to sorting by createdAt descending.
    /// - Returns: Array of Note entities matching the criteria
    func fetchNotes(
        predicate: Predicate<Note>? = nil,
        sortBy: [SortDescriptor<Note>] = [SortDescriptor(\.createdAt, order: .reverse)]
    ) -> [Note] {
        var descriptor = FetchDescriptor<Note>()
        if let predicate = predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Fetch notes for a specific student using search index attributes
    /// - Parameter studentID: The UUID of the student
    /// - Returns: Array of Notes visible to the student (scoped to them or all)
    func fetchNotesForStudent(studentID: UUID) -> [Note] {
        // Avoid SwiftData predicate translation to reduce crash risk.
        let allNotes = context.safeFetch(FetchDescriptor<Note>())
        var notes = allNotes.filter { note in
            note.searchIndexStudentID == studentID || note.scopeIsAll
        }

        // Also fetch notes that have student links (for multi-student scope)
        // NoteStudentLink stores studentID as String for CloudKit compatibility
        let studentIDString = studentID.uuidString
        let allLinks = context.safeFetch(FetchDescriptor<NoteStudentLink>())
        let linkedNotes = allLinks
            .filter { $0.studentID == studentIDString }
            .compactMap { $0.note }

        if !linkedNotes.isEmpty {
            notes.append(contentsOf: linkedNotes)
        }

        let deduped = Dictionary(grouping: notes, by: { $0.id })
            .compactMap { $0.value.first }
        return deduped.sorted { $0.createdAt > $1.createdAt }
    }

    // MARK: - Create

    /// Create a new Note
    /// - Parameters:
    ///   - body: The note content
    ///   - category: The note category. Defaults to .general
    ///   - scope: The note scope (all, student, or students). Defaults to .all
    ///   - isPinned: Whether the note is pinned. Defaults to false
    ///   - includeInReport: Whether to include in reports. Defaults to false
    ///   - lesson: Optional lesson relationship
    ///   - work: Optional work relationship
    ///   - studentLesson: Optional studentLesson relationship
    ///   - studentMeeting: Optional studentMeeting relationship
    ///   - imagePath: Optional image path
    ///   - reportedBy: Optional reporter type
    ///   - reporterName: Optional reporter name
    /// - Returns: The created Note entity
    @discardableResult
    func createNote(
        body: String,
        category: NoteCategory = .general,
        scope: NoteScope = .all,
        isPinned: Bool = false,
        includeInReport: Bool = false,
        lesson: Lesson? = nil,
        work: WorkModel? = nil,
        studentLesson: StudentLesson? = nil,
        studentMeeting: StudentMeeting? = nil,
        imagePath: String? = nil,
        reportedBy: String? = nil,
        reporterName: String? = nil
    ) -> Note {
        let note = Note(
            body: body,
            scope: scope,
            isPinned: isPinned,
            category: category,
            includeInReport: includeInReport,
            lesson: lesson,
            work: work,
            studentLesson: studentLesson,
            studentMeeting: studentMeeting,
            imagePath: imagePath,
            reportedBy: reportedBy,
            reporterName: reporterName
        )
        context.insert(note)

        // Sync student links for multi-student scope
        if case .students = scope {
            note.syncStudentLinks(in: context)
        }

        return note
    }

    // MARK: - Update

    /// Update an existing Note's properties
    /// - Parameters:
    ///   - id: The UUID of the note to update
    ///   - body: New body content (optional)
    ///   - category: New category (optional)
    ///   - scope: New scope (optional)
    ///   - isPinned: New pinned status (optional)
    ///   - includeInReport: New report inclusion status (optional)
    /// - Returns: true if update succeeded, false if note not found
    @discardableResult
    func updateNote(
        id: UUID,
        body: String? = nil,
        category: NoteCategory? = nil,
        scope: NoteScope? = nil,
        isPinned: Bool? = nil,
        includeInReport: Bool? = nil
    ) -> Bool {
        guard let note = fetchNote(id: id) else { return false }

        if let body = body {
            note.body = body
        }
        if let category = category {
            note.category = category
        }
        if let scope = scope {
            note.scope = scope
            note.syncStudentLinks(in: context)
        }
        if let isPinned = isPinned {
            note.isPinned = isPinned
        }
        if let includeInReport = includeInReport {
            note.includeInReport = includeInReport
        }

        note.updatedAt = Date()
        return true
    }

    // MARK: - Delete

    /// Delete a Note by ID
    func deleteNote(id: UUID) throws {
        guard let note = fetchNote(id: id) else { return }
        note.deleteAssociatedImage()
        context.delete(note)
        try context.save()
    }
}
