import Foundation
import SwiftData

@MainActor
struct WorkRepository {
    let context: ModelContext

    // MARK: - Fetch

    /// Fetch WorkModel by ID
    func fetchWorkModel(id: UUID) -> WorkModel? {
        let descriptor = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id })
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
        // Map WorkKind to WorkType
        let workType: WorkModel.WorkType = {
            if let kind = kind {
                switch kind {
                case .practiceLesson: return .practice
                case .followUpAssignment: return .followUp
                case .research: return .research
                }
            }
            // Default based on presentationID presence
            if presentationID != nil {
                return .practice
            }
            return .followUp
        }()
        
        // Determine studentLessonID from presentationID if available
        var studentLessonID: UUID? = presentationID
        
        // If presentationID is not available, try to find the StudentLesson
        if studentLessonID == nil {
            // Fetch candidates by lessonID (studentIDs is @Transient and can't be queried in SwiftData)
            let descriptor = FetchDescriptor<StudentLesson>(
                predicate: #Predicate { sl in
                    sl.lessonID == lessonID.uuidString
                }
            )
            // Filter in memory using the computed studentIDs property
            if let sl = (try? context.fetch(descriptor))?.first(where: { $0.studentIDs.contains(studentID.uuidString) }) {
                studentLessonID = sl.id
            }
        }
        
        // Create WorkModel
        let work = WorkModel(
            id: UUID(),
            title: title ?? "",
            workType: workType,
            studentLessonID: studentLessonID,
            notes: "",
            createdAt: Date(),
            completedAt: nil,
            participants: [],
            // Migration-ready fields
            kind: kind,
            status: .active,
            assignedAt: Date(),
            lastTouchedAt: nil,
            dueAt: scheduledDate,
            completionOutcome: nil,
            legacyContractID: nil
        )
        
        // Ensure identity fields are always populated for the new WorkModel.
        // These are required for Open Work and other UI to resolve student/lesson/presentation.
        work.studentID = studentID.uuidString
        work.lessonID = lessonID.uuidString
        work.presentationID = presentationID?.uuidString
        work.legacyStudentLessonID = studentLessonID?.uuidString
        
        // Create participant for the student
        let participant = WorkParticipantEntity(
            studentID: studentID,
            completedAt: nil,
            work: work
        )
        work.participants = [participant]
        
        // Link work to Track if lesson belongs to a track
        if let lesson = try? context.fetch(FetchDescriptor<Lesson>(
            predicate: #Predicate { $0.id == lessonID }
        )).first {
            let subject = lesson.subject.trimmed()
            let group = lesson.group.trimmed()
            if !subject.isEmpty && !group.isEmpty,
               GroupTrackService.isTrack(subject: subject, group: group, modelContext: context),
               let track = try? GroupTrackService.getOrCreateTrack(
                   subject: subject,
                   group: group,
                   modelContext: context
               ) {
                // Set track ID on WorkModel
                work.trackID = track.id.uuidString
                
                // Find the TrackStep for this lesson
                let allSteps = (try? context.fetch(FetchDescriptor<TrackStep>())) ?? []
                if let step = allSteps.first(where: {
                    $0.track?.id == track.id && $0.lessonTemplateID == lessonID
                }) {
                    work.trackStepID = step.id.uuidString
                }
            }
        }
        
        context.insert(work)
        try context.save()
        return work
    }
    
    // MARK: - Update

    /// Mark a WorkModel as completed
    func markWorkCompleted(id: UUID, outcome: CompletionOutcome? = nil, note: String? = nil) throws {
        guard let work = fetchWorkModel(id: id) else { return }
        work.status = .complete
        work.completedAt = Date()
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

