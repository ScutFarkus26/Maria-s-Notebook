import Foundation
import OSLog
import CoreData

@MainActor
struct WorkRepository {
    private static let logger = Logger.work

    let context: NSManagedObjectContext

    init(context: NSManagedObjectContext) {
        self.context = context
    }

    // Deprecated ModelContext init removed - no longer needed with Core Data.

    // MARK: - CDTrackEntity Linking Helper

    /// Links a work item to its associated track and step if the lesson belongs to a track
    private func linkWorkToTrack(_ work: CDWorkModel, lessonID: UUID) {
        let request = CDFetchRequest(CDLesson.self)
        request.predicate = NSPredicate(format: "id == %@", lessonID as CVarArg)
        request.fetchLimit = 1
        guard let lesson = context.safeFetchFirst(request) else { return }

        let subject = lesson.subject.trimmed()
        let group = lesson.group.trimmed()

        guard !subject.isEmpty, !group.isEmpty,
              GroupTrackService.isTrack(subject: subject, group: group, context: context) else { return }

        let track: CDTrackEntity
        do {
            track = try GroupTrackService.getOrCreateTrack(
                subject: subject,
                group: group,
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
        return context.safeFetch(request)
            .first(where: { $0.studentIDs.contains(studentID.uuidString) })?
            .id
    }

    // MARK: - Fetch

    /// Fetch CDWorkModel by ID
    func fetchWorkModel(id: UUID) -> CDWorkModel? {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return context.safeFetchFirst(request)
    }

    /// Fetch multiple CDWorkModel entities
    /// - Parameters:
    ///   - predicate: Optional predicate to filter work items. If nil, fetches all.
    ///   - sortDescriptors: Optional sort descriptors. Defaults to sorting by createdAt descending.
    /// - Returns: Array of CDWorkModel entities matching the criteria
    func fetchWorkModels(
        predicate: NSPredicate? = nil,
        sortDescriptors: [NSSortDescriptor] = [NSSortDescriptor(key: "createdAt", ascending: false)]
    ) -> [CDWorkModel] {
        let request = CDFetchRequest(CDWorkModel.self)
        if let predicate {
            request.predicate = predicate
        }
        request.sortDescriptors = sortDescriptors
        return context.safeFetch(request)
    }

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
        sampleWorkID: UUID? = nil
    ) throws -> CDWorkModel {
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
        work.completionOutcome = nil
        work.legacyContractID = nil

        // Populate identity fields for UI resolution
        work.studentID = studentID.uuidString
        work.lessonID = lessonID.uuidString
        work.presentationID = presentationID?.uuidString
        work.legacyStudentLessonID = studentLessonID?.uuidString

        // Create participant
        let participant = CDWorkParticipantEntity(context: context)
        participant.studentID = studentID.uuidString
        participant.completedAt = nil
        participant.work = work

        // Link to track if applicable
        linkWorkToTrack(work, lessonID: lessonID)

        // If a sample work template was specified, copy its steps into the new work
        if let swID = sampleWorkID {
            let swRequest = CDFetchRequest(CDSampleWorkEntity.self)
            swRequest.predicate = NSPredicate(format: "id == %@", swID as CVarArg)
            swRequest.fetchLimit = 1
            if let sampleWork = context.safeFetchFirst(swRequest) {
                let stepService = WorkStepService(context: context)
                let swService = SampleWorkService(context: context)
                try swService.instantiate(sampleWork: sampleWork, into: work, stepService: stepService)
            }
        }

        context.safeSave()
        return work
    }

    // MARK: - Update

    /// Mark a CDWorkModel as completed
    func markWorkCompleted(id: UUID, outcome: CompletionOutcome? = nil, note: String? = nil) {
        guard let work = fetchWorkModel(id: id) else { return }
        work.status = .complete
        work.completedAt = AppCalendar.startOfDay(Date())
        if let outcome {
            work.completionOutcome = outcome
        }
        if let note, !note.isEmpty {
            work.setLegacyNoteText(note, in: context)
        }
        context.safeSave()
        HapticService.shared.notification(.success)
    }

    /// Update a CDWorkModel's status
    func updateWorkStatus(id: UUID, status: WorkStatus) {
        guard let work = fetchWorkModel(id: id) else { return }
        work.status = status
        context.safeSave()
    }

    // MARK: - Delete

    func deleteWork(id: UUID) {
        guard let work = fetchWorkModel(id: id) else { return }
        context.delete(work)
        context.safeSave()
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
