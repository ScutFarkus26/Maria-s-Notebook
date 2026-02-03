import Foundation
import SwiftData

@MainActor
struct WorkRepository {
    let context: ModelContext

    // MARK: - Track Linking Helper

    /// Links a work item to its associated track and step if the lesson belongs to a track
    private func linkWorkToTrack(_ work: WorkModel, lessonID: UUID) {
        var descriptor = FetchDescriptor<Lesson>(
            predicate: #Predicate { $0.id == lessonID }
        )
        descriptor.fetchLimit = 1
        guard let lesson = try? context.fetch(descriptor).first else { return }

        let subject = lesson.subject.trimmed()
        let group = lesson.group.trimmed()

        guard !subject.isEmpty, !group.isEmpty,
              GroupTrackService.isTrack(subject: subject, group: group, modelContext: context),
              let track = try? GroupTrackService.getOrCreateTrack(
                  subject: subject,
                  group: group,
                  modelContext: context
              ) else { return }

        work.trackID = track.id.uuidString

        let allSteps = (try? context.fetch(FetchDescriptor<TrackStep>())) ?? []
        if let step = allSteps.first(where: {
            $0.track?.id == track.id && $0.lessonTemplateID == lessonID
        }) {
            work.trackStepID = step.id.uuidString
        }
    }

    /// Resolves the studentLessonID for a work item
    private func resolveStudentLessonID(studentID: UUID, lessonID: UUID, presentationID: UUID?) -> UUID? {
        if let presentationID = presentationID {
            return presentationID
        }

        let descriptor = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { sl in
                sl.lessonID == lessonID.uuidString
            }
        )
        return (try? context.fetch(descriptor))?
            .first(where: { $0.studentIDs.contains(studentID.uuidString) })?
            .id
    }

    // MARK: - Fetch

    /// Fetch WorkModel by ID
    func fetchWorkModel(id: UUID) -> WorkModel? {
        var descriptor = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return (try? context.fetch(descriptor))?.first
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
        return (try? context.fetch(descriptor)) ?? []
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
        scheduledDate: Date? = nil
    ) throws -> WorkModel {
        let workType = kind?.asWorkType ?? (presentationID != nil ? .practice : .followUp)
        let studentLessonID = resolveStudentLessonID(studentID: studentID, lessonID: lessonID, presentationID: presentationID)

        let work = WorkModel(
            id: UUID(),
            title: title ?? "",
            workType: workType,
            studentLessonID: studentLessonID,
            notes: "",
            createdAt: Date(),
            completedAt: nil,
            participants: [],
            kind: kind,
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
            work.notes = note
        }
        try context.save()
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
    func toggleCompletion(workID: UUID, studentID: UUID) throws {
        guard let work = fetchWorkModel(id: workID) else { return }
        if work.isStudentCompleted(studentID) {
            work.markStudent(studentID, completedAt: nil)
        } else {
            work.markStudent(studentID, completedAt: Date())
        }
        try context.save()
    }
}
