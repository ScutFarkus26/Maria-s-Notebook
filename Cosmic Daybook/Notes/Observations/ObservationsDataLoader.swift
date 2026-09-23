import Foundation
import OSLog
import CoreData

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
    static func loadAllNotes(context: NSManagedObjectContext) -> [UnifiedObservationItem] {
        var allItems: [UnifiedObservationItem] = []

        do {
            let noteFetch = CDFetchRequest(CDNote.self)
            noteFetch.sortDescriptors = [NSSortDescriptor(keyPath: \CDNote.createdAt, ascending: false)]
            // `work` is the one relationship whose *contents* the context label
            // reads (its title); prefetch it instead of faulting a work per row.
            noteFetch.relationshipKeyPathsForPrefetching = ["work"]
            let notes: [CDNote] = try context.fetch(noteFetch)
            // `lesson` and `communityTopic` are id lookups, not relationships:
            // each read ran its own fetch. Resolve them once for the whole list.
            let lookup = ContextLookup(notes: notes, context: context)
            for note in notes {
                // Skip notes with empty body and no image (e.g., leftover from check-in migrations)
                if note.body.trimmed().isEmpty && (note.imagePath ?? "").isEmpty {
                    continue
                }
                guard let noteID = note.id else { continue }
                let studentIDs = studentIDsFromScope(note.scope)
                let contextText = Self.contextText(for: note, lookup: lookup)
                allItems.append(UnifiedObservationItem(
                    id: noteID,
                    date: note.createdAt ?? Date(),
                    body: note.body,
                    tags: (note.tags as? [String]) ?? [],
                    includeInReport: note.includeInReport,
                    imagePath: note.imagePath,
                    contextText: contextText,
                    studentIDs: studentIDs,
                    source: .note(note)
                ))
            }
        } catch {
            logger.error("Error fetching CDNote objects: \(error)")
        }

        // Sort by date (newest first)
        allItems.sort { $0.date > $1.date }

        return allItems
    }

    // MARK: - Context Text

    /// The lessons and community topics the notes point at, by id — what
    /// `CDNote.lesson` / `.communityTopic` would each fetch on their own.
    /// Where two rows share an id, the first one the fetch returns wins, as
    /// with those accessors' `fetchLimit = 1`.
    struct ContextLookup {
        let lessons: [UUID: CDLesson]
        let topics: [UUID: CDCommunityTopicEntity]

        init(notes: [CDNote], context: NSManagedObjectContext) {
            let lessonIDs = Set(notes.compactMap { $0.lessonID.flatMap(UUID.init(uuidString:)) })
            let topicIDs = Set(notes.compactMap { $0.communityTopicID.flatMap(UUID.init(uuidString:)) })
            lessons = Self.byID(CDLesson.self, ids: lessonIDs, context: context)
            topics = Self.byID(CDCommunityTopicEntity.self, ids: topicIDs, context: context)
        }

        private static func byID<T: NSManagedObject>(
            _ type: T.Type, ids: Set<UUID>, context: NSManagedObjectContext
        ) -> [UUID: T] {
            guard !ids.isEmpty else { return [:] }
            let request = CDFetchRequest(type)
            request.predicate = NSPredicate(format: "id IN %@", Array(ids))
            var result: [UUID: T] = [:]
            for object in context.safeFetch(request) {
                guard let id = object.value(forKey: "id") as? UUID, result[id] == nil else { continue }
                result[id] = object
            }
            return result
        }
    }

    // The badge naming what a note is attached to.
    // swiftlint:disable:next cyclomatic_complexity
    static func contextText(for note: CDNote, lookup: ContextLookup) -> String? {
        if let lessonID = note.lessonID, let uuid = UUID(uuidString: lessonID), let lesson = lookup.lessons[uuid] {
            return "Lesson: \(lesson.name)"
        }
        if let work = note.work { return "Work: \(work.title)" }
        if note.lessonAssignment != nil { return "Presentation" }
        if note.attendanceRecordID != nil { return "Attendance" }
        if note.workCheckIn != nil { return "Check-In" }
        if note.workCompletionRecord != nil { return "Completion" }
        if note.studentMeeting != nil { return "Meeting" }
        if note.projectSession != nil { return "Session" }
        if let topicID = note.communityTopicID, let uuid = UUID(uuidString: topicID),
           let communityTopic = lookup.topics[uuid] {
            return "Topic: \(communityTopic.title)"
        }
        if note.reminder != nil { return "Reminder" }
        if note.schoolDayOverride != nil { return "Override" }
        return nil
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
        existingCache: [UUID: CDStudent],
        context: NSManagedObjectContext
    ) -> [UUID: CDStudent] {
        let idsNeeded = Set(items.flatMap { $0.studentIDs })
        let missing = idsNeeded.filter { existingCache[$0] == nil }
        guard !missing.isEmpty else { return existingCache }

        var updatedCache = existingCache
        // NOTE: SwiftData #Predicate doesn't support capturing local Set variables,
        // so we fetch all and filter in memory
        let allStudents: [CDStudent]
        do {
            allStudents = try context.fetch(CDFetchRequest(CDStudent.self)).filterEnrolled()
        } catch {
            logger.warning("Failed to fetch students: \(error)")
            allStudents = []
        }
        let fetched = allStudents.filter { guard let id = $0.id else { return false }; return missing.contains(id) }
        for s in fetched { guard let id = s.id else { continue }; updatedCache[id] = s }

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
