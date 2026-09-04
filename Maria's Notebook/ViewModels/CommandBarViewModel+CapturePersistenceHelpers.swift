import CoreData
import Foundation

extension CommandBarViewModel {
    func fetchStudents(ids: [UUID], context: NSManagedObjectContext) throws -> [CDStudent] {
        guard !ids.isEmpty else { return [] }
        let request = CDFetchRequest(CDStudent.self)
        request.predicate = NSPredicate(format: "id IN %@", ids)
        let fetched = try context.fetch(request).uniqueByID
        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($0.element, $0.offset) })
        return fetched.sorted { (order[$0.id ?? UUID()] ?? .max) < (order[$1.id ?? UUID()] ?? .max) }
    }

    func fetchLesson(id: UUID, context: NSManagedObjectContext) throws -> CDLesson? {
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return try context.fetch(request).first
    }

    func reusableAssignment(
        lessonID: UUID,
        studentIDs: [UUID],
        context: NSManagedObjectContext
    ) throws -> CDLessonAssignment? {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
        let expected = Set(studentIDs)
        return try context.fetch(request)
            .filter { !$0.isPresented && Set($0.studentUUIDs) == expected }
            .sorted {
                if $0.isScheduled != $1.isScheduled { return $0.isScheduled }
                return ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast)
            }
            .first
    }

    /// Resolves the presentation that the guide just recorded. This path must
    /// never guess, create a replacement, or run the lifecycle a second time.
    func exactRecordedAssignment(
        id: UUID,
        lessonID: UUID,
        studentIDs: [UUID],
        context: NSManagedObjectContext
    ) throws -> CDLessonAssignment {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        guard let assignment = try context.fetch(request).first else {
            throw CaptureSaveError.invalid(
                "The presentation you just recorded could not be found. Nothing was saved."
            )
        }
        guard assignment.isPresented else {
            throw CaptureSaveError.invalid(
                "The selected presentation has not been recorded as presented yet. Nothing was saved."
            )
        }
        guard assignment.lessonIDUUID == lessonID else {
            throw CaptureSaveError.invalid(
                "The reviewed lesson does not match the presentation you just recorded. Nothing was saved."
            )
        }
        guard Set(assignment.studentUUIDs) == Set(studentIDs) else {
            throw CaptureSaveError.invalid(
                "The reviewed children do not match the presentation you just recorded. Nothing was saved."
            )
        }
        return assignment
    }

    func createWorkIfNeeded(
        kind: WorkKind,
        entry: StudentCaptureProposal,
        persistence: CapturePersistenceContext
    ) throws -> Bool {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(
            format: "presentationID == %@ AND studentID == %@ AND kindRaw == %@",
            persistence.presentationID.uuidString,
            entry.studentID.uuidString,
            kind.rawValue
        )
        request.fetchLimit = 1
        guard try persistence.context.fetch(request).isEmpty else { return false }

        let defaultTitle = kind == .practiceLesson
            ? "Practice: \(persistence.lessonName)"
            : "Follow up: \(persistence.lessonName)"
        let title = entry.followUpDetail.trimmed().isEmpty
            ? defaultTitle
            : entry.followUpDetail.trimmed()
        _ = try WorkRepository(context: persistence.context).createWork(
            studentID: entry.studentID,
            lessonID: persistence.lessonID,
            title: title,
            kind: kind,
            presentationID: persistence.presentationID,
            saveImmediately: false
        )
        return true
    }

    func createRepresentationIfNeeded(
        studentID: UUID,
        lesson: CDLesson,
        context: NSManagedObjectContext
    ) throws {
        guard let lessonID = lesson.id else { return }
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonID.uuidString)
        let alreadyPlanned = try context.fetch(request).contains {
            !$0.isPresented && $0.studentUUIDs.contains(studentID)
        }
        guard !alreadyPlanned,
              let student = try fetchStudents(ids: [studentID], context: context).first else { return }
        _ = PresentationFactory.makeDraft(lesson: lesson, students: [student], context: context)
    }

    func markObservationForFollowUp(
        entry: StudentCaptureProposal,
        assignment: CDLessonAssignment,
        context: NSManagedObjectContext
    ) {
        let body = entry.observation.trimmed()
        let notes = (assignment.unifiedNotes?.allObjects as? [CDNote]) ?? []
        if let note = notes.first(where: {
            $0.body.trimmed() == body && $0.scope == .student(entry.studentID)
        }) {
            note.needsFollowUp = true
            note.updatedAt = Date()
            return
        }

        // This normally only occurs while the relationship has not refreshed.
        let note = CDNote(context: context)
        note.body = body
        note.scope = .student(entry.studentID)
        note.lessonID = assignment.lessonID
        note.lessonAssignment = assignment
        note.needsFollowUp = true
        note.syncStudentLinks(in: context)
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
