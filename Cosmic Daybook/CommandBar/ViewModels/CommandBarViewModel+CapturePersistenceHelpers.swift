import CoreData
import Foundation

extension CommandBarViewModel {
    /// The chosen children in the order they were chosen, one row per id.
    func fetchStudents(ids: [UUID], context: NSManagedObjectContext) throws -> [CDStudent] {
        let fetched = try StudentRepository(context: context).fetchStudents(ids: ids).uniqueByID
        let order = Dictionary(
            ids.enumerated().map { ($0.element, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        return fetched.sorted { (order[$0.id ?? UUID()] ?? .max) < (order[$1.id ?? UUID()] ?? .max) }
    }

    func fetchLesson(id: UUID, context: NSManagedObjectContext) throws -> CDLesson? {
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func makeStandaloneObservationNotes(
        proposal: CaptureProposal,
        context: NSManagedObjectContext
    ) -> [CDNote] {
        var notes: [CDNote] = []
        let shared = proposal.groupObservation.trimmed()
        if !shared.isEmpty {
            let note = CDNote(context: context)
            note.body = shared
            note.scope = proposal.studentIDs.isEmpty
                ? .all
                : (proposal.studentIDs.count == 1
                    ? .student(proposal.studentIDs[0])
                    : .students(proposal.studentIDs))
            note.lessonID = proposal.lessonID?.uuidString
            note.syncStudentLinks(in: context)
            notes.append(note)
        }

        for entry in proposal.studentEntries where !entry.observation.trimmed().isEmpty {
            let note = CDNote(context: context)
            note.body = entry.observation.trimmed()
            note.scope = .student(entry.studentID)
            note.lessonID = proposal.lessonID?.uuidString
            note.syncStudentLinks(in: context)
            notes.append(note)
        }
        return notes
    }
}
