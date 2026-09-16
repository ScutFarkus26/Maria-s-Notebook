import Foundation
import OSLog
import CoreData

struct WorkRepository: Repository {
    typealias Model = CDWorkModel

    private static let logger = Logger.work

    let context: NSManagedObjectContext

    // MARK: - Assignment Rules

    enum AssignmentError: LocalizedError, Equatable {
        /// The child's record says withdrawn or transferred. Work is for
        /// children in the room; a former student is corrected in her
        /// profile, not given new work.
        case studentNotEnrolled(name: String, status: String)

        var errorDescription: String? {
            switch self {
            case let .studentNotEnrolled(name, status):
                return "\(name) is \(status) and cannot be given work. Only enrolled students can be assigned work."
            }
        }
    }

    /// Refuses a student whose record is on file and not enrolled. A student
    /// id with no record passes: tests and imports create work for children
    /// whose rows arrive later, and that was never the failure here.
    func requireEnrolled(_ studentID: UUID) throws {
        guard let student = context.object(CDStudent.self, id: studentID), !student.isEnrolled else { return }
        throw AssignmentError.studentNotEnrolled(name: student.fullName, status: student.enrollmentStatusRaw)
    }

    // MARK: - CDTrackEntity Linking Helper

    /// Links a work item to its associated track and step if the lesson belongs to a track
    private func linkWorkToTrack(_ work: CDWorkModel, lessonID: UUID) {
        guard let lesson = context.object(CDLesson.self, id: lessonID) else { return }

        let area = lesson.area.trimmed()
        let sequence = lesson.sequence.trimmed()

        guard !area.isEmpty, !sequence.isEmpty,
              SequenceTrackService.isTrack(area: area, sequence: sequence, context: context) else { return }

        let track: CDTrackEntity
        do {
            track = try SequenceTrackService.getOrCreateTrack(
                area: area,
                sequence: sequence,
                context: context
            )
        } catch {
            Self.logger.warning("Failed to get or create track: \(error)")
            return
        }

        work.trackID = track.id?.uuidString

        let stepRequest = CDFetchRequest(CDTrackStepEntity.self)
        let steps = context.safeFetch(stepRequest)
        if let step = steps.first(where: {
            $0.track?.id == track.id && $0.lessonTemplateID == lessonID
        }) {
            work.trackStepID = step.id?.uuidString
        }
    }

    /// Resolves the presentationID for a work item
    private func resolvePresentationID(studentID: UUID, lessonID: UUID, presentationID: UUID?) -> UUID? {
        if let presentationID {
            return presentationID
        }

        let lessonIDString = lessonID.uuidString
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "lessonID == %@", lessonIDString)
        let candidates = context.safeFetch(request)
            .filter { $0.studentIDs.contains(studentID.uuidString) }
        return Self.preferredAssignment(among: candidates)?.id
    }

    /// Picks the assignment a work item should link to. Follow-up work belongs to the
    /// presentation the student just received, so prefer presented assignments (most
    /// recent first) over drafts/scheduled ones. "Previously Presented" records are
    /// undated, so fall back to createdAt. Also used by the one-shot backfill that
    /// links pre-fix work items (DataMigrations+WorkPresentationLinkBackfill).
    static func preferredAssignment(among candidates: [CDLessonAssignment]) -> CDLessonAssignment? {
        let presented = candidates
            .filter(\.isPresented)
            .max { lhs, rhs in
                let lhsDate = lhs.presentedAt ?? lhs.createdAt ?? .distantPast
                let rhsDate = rhs.presentedAt ?? rhs.createdAt ?? .distantPast
                return lhsDate < rhsDate
            }
        let fallback = candidates.max {
            ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast)
        }
        return presented ?? fallback
    }

    // MARK: - Fetch

    /// Fetch CDWorkModel by ID
    func fetchWorkModel(id: UUID) -> CDWorkModel? { fetch(id: id) }

    // MARK: - Create

    /// Create a new CDWorkModel for a single student
    @discardableResult
    func createWork(
        studentID: UUID,
        lessonID: UUID,
        title: String? = nil,
        kind: WorkKind? = nil,
        presentationID: UUID? = nil,
        scheduledDate: Date? = nil,
        sampleWorkID: UUID? = nil,
        saveImmediately: Bool = true
    ) throws -> CDWorkModel {
        try requireEnrolled(studentID)

        // Use WorkKind directly (new system), with smart defaults
        let workKind = kind ?? (presentationID != nil ? .practiceLesson : .followUpAssignment)
        let studentLessonID = resolvePresentationID(
            studentID: studentID, lessonID: lessonID,
            presentationID: presentationID
        )

        let work = CDWorkModel(context: context)
        work.title = title ?? ""
        work.kind = workKind
        work.studentLessonID = studentLessonID
        work.createdAt = Date()
        work.completedAt = nil
        work.status = .active
        work.assignedAt = Date()
        work.lastTouchedAt = nil
        work.dueAt = scheduledDate

        // Populate identity fields for UI resolution. presentationID must carry the
        // resolved assignment ID (not just the raw parameter, which most callers omit):
        // readiness, blocking, and mastery checks all key work on presentationID, so an
        // unlinked work item can never satisfy a practice gate.
        work.studentID = studentID.uuidString
        work.lessonID = lessonID.uuidString
        work.presentationID = studentLessonID?.uuidString

        // Create participant
        let participant = CDWorkParticipantEntity(context: context)
        participant.studentID = studentID.uuidString
        participant.completedAt = nil
        participant.work = work

        // Link to track if applicable
        linkWorkToTrack(work, lessonID: lessonID)

        // If a sample work template was specified, copy its steps into the new work
        if let swID = sampleWorkID {
            if let sampleWork = context.object(CDSampleWorkEntity.self, id: swID) {
                let stepService = WorkStepService(context: context)
                let swService = SampleWorkService(context: context)
                try swService.instantiate(sampleWork: sampleWork, into: work, stepService: stepService)
            }
        }

        if saveImmediately {
            context.safeSave()
        }
        return work
    }

    // MARK: - Update

    /// Close a CDWorkModel with a verdict (`.done` when the guide gave none).
    func markWorkCompleted(id: UUID, status: WorkStatus = .done, note: String? = nil) {
        guard let work = fetchWorkModel(id: id) else { return }
        work.status = status.isClosed ? status : .done
        work.completedAt = AppCalendar.startOfDay(Date())
        if let note, !note.isEmpty {
            work.setLegacyNoteText(note, in: context)
        }
        // Only signal success and run downstream unlocking if the save actually persisted —
        // a success haptic / auto-unlock on a failed save would be misleading.
        guard context.safeSave() else { return }
        HapticService.shared.notification(.success)
    }

    /// Update a CDWorkModel's status
    func updateWorkStatus(id: UUID, status: WorkStatus) {
        guard let work = fetchWorkModel(id: id) else { return }
        work.status = status
        context.safeSave()
    }

    // MARK: - Delete

    /// Deletes through `WorkDeletionService`, which also strips the deleted
    /// owner from surviving linked copies and sweeps the records that key work
    /// by id string. A bare `context.delete(work)` leaves both behind.
    func deleteWork(id: UUID) {
        guard let work = fetchWorkModel(id: id) else { return }
        do {
            try WorkDeletionService(context: context).delete([work])
        } catch {
            Self.logger.error("Failed to delete work \(id): \(error)")
        }
    }

    // MARK: - Completion Toggle

    /// Toggle completion for a student on a CDWorkModel
    /// Uses WorkCompletionService for proper historical tracking
    func toggleCompletion(workID: UUID, studentID: UUID) throws {
        guard let work = fetchWorkModel(id: workID) else { return }

        if work.isStudentCompleted(studentID) {
            // Un-complete: Remove from participant (historical records preserved)
            if let participant = work.participant(for: studentID) {
                participant.completedAt = nil
            }
        } else {
            // Complete: Use WorkCompletionService for proper historical tracking
            try WorkCompletionService.markCompleted(workID: workID, studentID: studentID, in: context)
            // Also update participant for backwards compatibility
            if let participant = work.participant(for: studentID) {
                participant.completedAt = Date()
            }
        }

        context.safeSave()
    }
}
