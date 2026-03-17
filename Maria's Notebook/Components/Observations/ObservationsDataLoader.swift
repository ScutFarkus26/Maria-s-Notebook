import Foundation
import OSLog
import SwiftData

// MARK: - Observations Data Loader

/// Loads and manages note data for the ObservationsView.
enum ObservationsDataLoader {
    private static let logger = Logger.notes

    // MARK: - Load All Notes

    /// Loads all notes from the database.
    ///
    /// - Parameters:
    ///   - context: Model context for fetching
    ///   - contextTextProvider: Closure to generate context text for a note
    /// - Returns: Array of UnifiedObservationItem sorted by date (newest first)
    static func loadAllNotes(
        context: ModelContext,
        contextTextProvider: (Note) -> String?
    ) -> [UnifiedObservationItem] {
        var allItems: [UnifiedObservationItem] = []

        do {
            let noteFetch = FetchDescriptor<Note>(
                sortBy: [SortDescriptor(\Note.createdAt, order: .reverse)]
            )
            let notes: [Note] = try context.fetch(noteFetch)
            for note in notes {
                // Skip notes with empty body and no image (e.g., leftover from check-in migrations)
                if note.body.trimmed().isEmpty && (note.imagePath ?? "").isEmpty {
                    continue
                }
                let studentIDs = studentIDsFromScope(note.scope)
                let contextText = contextTextProvider(note)
                allItems.append(UnifiedObservationItem(
                    id: note.id,
                    date: note.createdAt,
                    body: note.body,
                    tags: note.tags,
                    includeInReport: note.includeInReport,
                    imagePath: note.imagePath,
                    contextText: contextText,
                    studentIDs: studentIDs,
                    source: .note(note)
                ))
            }
        } catch {
            logger.error("Error fetching Note objects: \(error)")
        }

        // Sort by date (newest first)
        allItems.sort { $0.date > $1.date }

        return allItems
    }

    // MARK: - Load Students

    /// Loads students for the given note items.
    ///
    /// - Parameters:
    ///   - items: Items containing student IDs
    ///   - existingCache: Existing student cache to avoid re-fetching
    ///   - context: Model context for fetching
    /// - Returns: Updated student cache
    static func loadStudents(
        for items: [UnifiedObservationItem],
        existingCache: [UUID: Student],
        context: ModelContext
    ) -> [UUID: Student] {
        let idsNeeded = Set(items.flatMap { $0.studentIDs })
        let missing = idsNeeded.filter { existingCache[$0] == nil }
        guard !missing.isEmpty else { return existingCache }

        var updatedCache = existingCache
        // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
        // so we fetch all and filter in memory
        let allStudents: [Student]
        do {
            allStudents = try context.fetch(FetchDescriptor<Student>()).filter { $0.isEnrolled }
        } catch {
            logger.warning("Failed to fetch students: \(error)")
            allStudents = []
        }
        let fetched = allStudents.filter { missing.contains($0.id) }
        for s in fetched { updatedCache[s.id] = s }

        return updatedCache
    }

    // MARK: - Private Helpers

    private static func studentIDsFromScope(_ scope: NoteScope) -> [UUID] {
        switch scope {
        case .all: return []
        case .student(let id): return [id]
        case .students(let ids): return ids
        }
    }
}
