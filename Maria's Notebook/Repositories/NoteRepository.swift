//
//  NoteRepository.swift
//  Maria's Notebook
//
//  Repository for CDNote entity CRUD operations.
//

import Foundation
import OSLog
import CoreData

@MainActor
struct NoteRepository: SavingRepository {
    typealias Model = CDNote

    private static let logger = Logger.database

    let context: NSManagedObjectContext
    let saveCoordinator: SaveCoordinator?

    init(context: NSManagedObjectContext, saveCoordinator: SaveCoordinator? = nil) {
        self.context = context
        self.saveCoordinator = saveCoordinator
    }

    // MARK: - Fetch

    /// Fetch a CDNote by ID
    func fetchNote(id: UUID) -> CDNote? {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return context.safeFetchFirst(request)
    }

    /// Fetch multiple Notes with optional filtering and sorting
    func fetchNotes(
        predicate: NSPredicate? = nil,
        sortBy: [NSSortDescriptor] = [NSSortDescriptor(key: "createdAt", ascending: false)]
    ) -> [CDNote] {
        let request = CDFetchRequest(CDNote.self)
        request.predicate = predicate
        request.sortDescriptors = sortBy
        return context.safeFetch(request)
    }

    /// Fetch notes for a specific student using search index attributes
    func fetchNotesForStudent(studentID: UUID) -> [CDNote] {
        // Fetch all notes and filter in memory to avoid complex predicate issues
        let allNotes = context.safeFetch(CDFetchRequest(CDNote.self))
        var notes = allNotes.filter { note in
            note.searchIndexStudentID == studentID || note.scopeIsAll
        }

        // Also fetch notes that have student links (for multi-student scope)
        let studentIDString = studentID.uuidString
        let allLinks = context.safeFetch(CDFetchRequest(CDNoteStudentLink.self))
        let linkedNotes = allLinks
            .filter { $0.studentID == studentIDString }
            .compactMap(\.note)

        if !linkedNotes.isEmpty {
            notes.append(contentsOf: linkedNotes)
        }

        let deduped = Dictionary(grouping: notes, by: { $0.id })
            .compactMap { $0.value.first }
        return deduped.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
    }

    // MARK: - Create

    /// Create a new CDNote
    @discardableResult
    func createNote(
        body: String,
        tags: [String] = [],
        scope: NoteScope = .all,
        isPinned: Bool = false,
        includeInReport: Bool = false,
        needsFollowUp: Bool = false,
        lesson: CDLesson? = nil,
        work: CDWorkModel? = nil,
        studentMeeting: CDStudentMeeting? = nil,
        imagePath: String? = nil,
        reportedBy: String? = nil,
        reporterName: String? = nil
    ) -> CDNote {
        let note = CDNote(context: context)
        note.body = body
        note.tagsArray = tags
        note.scope = scope
        note.isPinned = isPinned
        note.includeInReport = includeInReport
        note.needsFollowUp = needsFollowUp
        note.lesson = lesson
        note.work = work
        note.studentMeeting = studentMeeting
        note.imagePath = imagePath
        note.reportedBy = reportedBy
        note.reporterName = reporterName

        // Sync student links for multi-student scope
        if case .students = scope {
            note.syncStudentLinks(in: context)
        }

        return note
    }

    // MARK: - Update

    /// Update an existing CDNote's properties
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

        if let body { note.body = body }
        if let tags { note.tagsArray = tags }
        if let scope {
            note.scope = scope
            note.syncStudentLinks(in: context)
        }
        if let isPinned { note.isPinned = isPinned }
        if let includeInReport { note.includeInReport = includeInReport }
        if let needsFollowUp { note.needsFollowUp = needsFollowUp }

        note.updatedAt = Date()
        return true
    }

    // MARK: - Delete

    /// Delete a CDNote by ID
    func deleteNote(id: UUID) throws {
        guard let note = fetchNote(id: id) else { return }
        note.deleteAssociatedImage()
        context.delete(note)
        try context.save()
    }
}
