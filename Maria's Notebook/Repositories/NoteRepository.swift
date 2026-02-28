//
//  NoteRepository.swift
//  Maria's Notebook
//
//  Repository for Note entity CRUD operations.
//  Follows the pattern established by WorkRepository.
//

import Foundation
import OSLog
import SwiftData

@MainActor
struct NoteRepository: SavingRepository {
    typealias Model = Note

    private static let logger = Logger.database

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
        return context.safeFetchFirst(descriptor)
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
        return context.safeFetch(descriptor)
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
    ///   - tags: Tags in "Name|Color" format. Defaults to empty
    ///   - scope: The note scope (all, student, or students). Defaults to .all
    ///   - isPinned: Whether the note is pinned. Defaults to false
    ///   - includeInReport: Whether to include in reports. Defaults to false
    ///   - needsFollowUp: Whether the note needs follow-up. Defaults to false
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
        tags: [String] = [],
        scope: NoteScope = .all,
        isPinned: Bool = false,
        includeInReport: Bool = false,
        needsFollowUp: Bool = false,
        lesson: Lesson? = nil,
        work: WorkModel? = nil,
        studentMeeting: StudentMeeting? = nil,
        imagePath: String? = nil,
        reportedBy: String? = nil,
        reporterName: String? = nil
    ) -> Note {
        let note = Note(
            body: body,
            scope: scope,
            isPinned: isPinned,
            tags: tags,
            includeInReport: includeInReport,
            needsFollowUp: needsFollowUp,
            lesson: lesson,
            work: work,
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
    ///   - tags: New tags array (optional)
    ///   - scope: New scope (optional)
    ///   - isPinned: New pinned status (optional)
    ///   - includeInReport: New report inclusion status (optional)
    ///   - needsFollowUp: New follow-up status (optional)
    /// - Returns: true if update succeeded, false if note not found
    @discardableResult
    func updateNote(
        id: UUID,
        body: String? = nil,
        tags: [String]? = nil,
        scope: NoteScope? = nil,
        isPinned: Bool? = nil,
        includeInReport: Bool? = nil,
        needsFollowUp: Bool? = nil
    ) -> Bool {
        guard let note = fetchNote(id: id) else { return false }

        if let body = body {
            note.body = body
        }
        if let tags = tags {
            note.tags = tags
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
        if let needsFollowUp = needsFollowUp {
            note.needsFollowUp = needsFollowUp
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
        do {
            try context.save()
        } catch {
            Self.logger.warning("Failed to save context: \(error, privacy: .public)")
            throw error
        }
    }
}
