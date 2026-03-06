import Foundation
import OSLog
import SwiftData

@MainActor
struct WorkRepository {
    private static let logger = Logger.work

    let context: ModelContext

    // MARK: - Helper Methods

    private func safeFetch<T>(_ descriptor: FetchDescriptor<T>, context: String = #function) -> [T] {
        do {
            return try self.context.fetch(descriptor)
        } catch {
            Self.logger.warning("\(context): Failed to fetch \(T.self): \(error)")
            return []
        }
    }

    private func safeFetchFirst<T>(_ descriptor: FetchDescriptor<T>, context: String = #function) -> T? {
        do {
            return try self.context.fetch(descriptor).first
        } catch {
            Self.logger.warning("\(context): Failed to fetch \(T.self): \(error)")
            return nil
        }
    }

    // MARK: - Track Linking Helper

    /// Links a work item to its associated track and step if the lesson belongs to a track
    private func linkWorkToTrack(_ work: WorkModel, lessonID: UUID) {
        var descriptor = FetchDescriptor<Lesson>(
            predicate: #Predicate { $0.id == lessonID }
        )
        descriptor.fetchLimit = 1
        guard let lesson = safeFetchFirst(descriptor) else { return }

        let subject = lesson.subject.trimmed()
        let group = lesson.group.trimmed()

        guard !subject.isEmpty, !group.isEmpty,
              GroupTrackService.isTrack(subject: subject, group: group, modelContext: context) else { return }

        let track: Track
        do {
            track = try GroupTrackService.getOrCreateTrack(
                subject: subject,
                group: group,
                modelContext: context
            )
        } catch {
            Self.logger.warning("Failed to get or create track: \(error)")
            return
        }

        work.trackID = track.id.uuidString

        let allSteps = safeFetch(FetchDescriptor<TrackStep>())
        if let step = allSteps.first(where: {
            $0.track?.id == track.id && $0.lessonTemplateID == lessonID
        }) {
            work.trackStepID = step.id.uuidString
        }
    }

    /// Resolves the presentationID for a work item
    private func resolvePresentationID(studentID: UUID, lessonID: UUID, presentationID: UUID?) -> UUID? {
        if let presentationID = presentationID {
            return presentationID
        }

        let lessonIDString = lessonID.uuidString
        let descriptor = FetchDescriptor<LessonAssignment>(
            predicate: #Predicate { la in
                la.lessonID == lessonIDString
            }
        )
        return safeFetch(descriptor)
            .first(where: { $0.studentIDs.contains(studentID.uuidString) })?
            .id
    }

    // MARK: - Fetch

    /// Fetch WorkModel by ID
    func fetchWorkModel(id: UUID) -> WorkModel? {
        var descriptor = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return safeFetchFirst(descriptor)
    }

    /// Fetch multiple WorkModel entities
    /// - Parameters:
    ///   - predicate: Optional predicate to filter work items. If nil, fetches all.
    ///   - sortBy: Optional sort descriptors. Defaults to sorting by createdAt descending.
    /// - Returns: Array of WorkModel entities matching the criteria
    func fetchWorkModels(
        predicate: Predicate<WorkModel>? = nil,
        sortBy: [SortDescriptor<WorkModel>] = [SortDescriptor(\.createdAt, order: .reverse)]
    ) -> [WorkModel] {
        var descriptor = FetchDescriptor<WorkModel>()
        if let predicate = predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy
        return safeFetch(descriptor)
    }

    // MARK: - Create

    /// Create a new WorkModel for a single student
    @discardableResult
    func createWork(
        studentID: UUID,
        lessonID: UUID,
        title: String? = nil,
        kind: WorkKind? = nil,
        presentationID: UUID? = nil,
        scheduledDate: Date? = nil,
        sampleWorkID: UUID? = nil
    ) throws -> WorkModel {
        // Use WorkKind directly (new system), with smart defaults
        let workKind = kind ?? (presentationID != nil ? .practiceLesson : .followUpAssignment)
        let studentLessonID = resolvePresentationID(
            studentID: studentID, lessonID: lessonID,
            presentationID: presentationID
        )

        let work = WorkModel(
            id: UUID(),
            title: title ?? "",
            kind: workKind,
            studentLessonID: studentLessonID,
            createdAt: Date(),
            completedAt: nil,
            participants: [],
            status: .active,
            assignedAt: Date(),
            lastTouchedAt: nil,
            dueAt: scheduledDate,
            completionOutcome: nil,
            legacyContractID: nil
        )

        // Populate identity fields for UI resolution
        work.studentID = studentID.uuidString
        work.lessonID = lessonID.uuidString
        work.presentationID = presentationID?.uuidString
        work.legacyStudentLessonID = studentLessonID?.uuidString

        // Create participant
        let participant = WorkParticipantEntity(studentID: studentID, completedAt: nil, work: work)
        work.participants = [participant]

        // Link to track if applicable
        linkWorkToTrack(work, lessonID: lessonID)

        context.insert(work)

        // If a sample work template was specified, copy its steps into the new work
        if let swID = sampleWorkID {
            var swDescriptor = FetchDescriptor<SampleWork>(
                predicate: #Predicate { $0.id == swID }
            )
            swDescriptor.fetchLimit = 1
            if let sampleWork = safeFetchFirst(swDescriptor) {
                let stepService = WorkStepService(context: context)
                let swService = SampleWorkService(context: context)
                try swService.instantiate(sampleWork: sampleWork, into: work, stepService: stepService)
            }
        }

        try context.save()
        return work
    }

    // MARK: - Update

    /// Mark a WorkModel as completed
    func markWorkCompleted(id: UUID, outcome: CompletionOutcome? = nil, note: String? = nil) throws {
        guard let work = fetchWorkModel(id: id) else { return }
        work.status = .complete
        work.completedAt = AppCalendar.startOfDay(Date())
        if let outcome = outcome {
            work.completionOutcome = outcome
        }
        if let note = note, !note.isEmpty {
            _ = work.setLegacyNoteText(note, in: context)
        }
        try context.save()
        HapticService.shared.notification(.success)
    }

    /// Update a WorkModel's status
    func updateWorkStatus(id: UUID, status: WorkStatus) throws {
        guard let work = fetchWorkModel(id: id) else { return }
        work.status = status
        try context.save()
    }

    // MARK: - Delete

    func deleteWork(id: UUID) throws {
        guard let work = fetchWorkModel(id: id) else { return }
        context.delete(work)
        try context.save()
    }

    // MARK: - Completion Toggle

    /// Toggle completion for a student on a WorkModel
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
        
        try context.save()
    }
}
