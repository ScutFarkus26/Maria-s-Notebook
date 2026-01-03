import Foundation
import SwiftData

@MainActor
struct WorkRepository {
    let context: ModelContext

    // MARK: - Fetch
    /// Fetch a single WorkContract by ID
    func fetchWork(id: UUID) -> WorkContract? {
        let descriptor = FetchDescriptor<WorkContract>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }
    
    /// Fetch multiple WorkContract entities
    /// - Parameters:
    ///   - predicate: Optional predicate to filter contracts. If nil, fetches all contracts.
    ///   - sortBy: Optional sort descriptors. Defaults to sorting by createdAt descending.
    /// - Returns: Array of WorkContract entities matching the criteria
    func fetchWorkContracts(
        predicate: Predicate<WorkContract>? = nil,
        sortBy: [SortDescriptor<WorkContract>] = [SortDescriptor(\.createdAt, order: .reverse)]
    ) -> [WorkContract] {
        var descriptor = FetchDescriptor<WorkContract>()
        if let predicate = predicate {
            descriptor.predicate = predicate
        }
        descriptor.sortBy = sortBy
        return (try? context.fetch(descriptor)) ?? []
    }
    
    /// Legacy method: Fetch WorkModel by ID (kept for backward compatibility with legacy data)
    @available(*, deprecated, message: "Use fetchWork(id:) to fetch WorkContract instead")
    func fetchWorkModel(id: UUID) -> WorkModel? {
        let descriptor = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Create (WorkContract)
    /// Create a new WorkContract for a single student
    @discardableResult
    func createWorkContract(
        studentID: UUID,
        lessonID: UUID,
        title: String? = nil,
        kind: WorkKind? = nil,
        presentationID: UUID? = nil,
        scheduledDate: Date? = nil
    ) throws -> WorkContract {
        let contract = WorkContract(
            id: UUID(),
            createdAt: Date(),
            studentID: studentID.uuidString,
            lessonID: lessonID.uuidString,
            presentationID: presentationID?.uuidString,
            title: title,
            status: .active,
            scheduledDate: scheduledDate,
            completedAt: nil,
            legacyStudentLessonID: nil,
            kind: kind
        )
        context.insert(contract)
        try context.save()
        return contract
    }
    
    // MARK: - Update (WorkContract)
    /// Mark a WorkContract as completed
    func markContractCompleted(id: UUID, outcome: CompletionOutcome? = nil, note: String? = nil) throws {
        guard let contract = fetchWork(id: id) else { return }
        contract.status = .complete
        contract.completedAt = Date()
        if let outcome = outcome {
            contract.completionOutcome = outcome
        }
        if let note = note {
            contract.completionNote = note
        }
        try context.save()
    }
    
    /// Update a WorkContract's status
    func updateContractStatus(id: UUID, status: WorkStatus) throws {
        guard let contract = fetchWork(id: id) else { return }
        contract.status = status
        try context.save()
    }

    // MARK: - Delete (WorkContract)
    func deleteWork(id: UUID) throws {
        guard let contract = fetchWork(id: id) else { return }
        // Resolve attributes that UI might still touch briefly
        _ = contract.title
        _ = contract.createdAt
        _ = contract.completedAt
        _ = contract.status
        _ = contract.studentID
        _ = contract.lessonID

        context.delete(contract)
        try context.save()
    }
    
    // MARK: - Legacy Methods (WorkModel) - Deprecated
    /// Legacy method: Create WorkModel (deprecated in favor of WorkContract)
    @available(*, deprecated, message: "Use createWorkContract instead. WorkModel is deprecated in favor of WorkContract.")
    @discardableResult
    func createWork(title: String,
                    studentIDs: [UUID],
                    type: WorkModel.WorkType,
                    studentLessonID: UUID?,
                    notes: String) throws -> WorkModel {
        let work = WorkModel(
            id: UUID(),
            title: title,
            workType: type,
            studentLessonID: studentLessonID,
            notes: notes,
            createdAt: Date()
        )
        work.participants = (work.participants ?? []) + studentIDs.map { sid in WorkParticipantEntity(studentID: sid, completedAt: nil, work: work) }
        context.insert(work)

        // Automatically schedule a default check-in (2 days offset)
        let cal = AppCalendar.shared
        let offsetDays = 2
        if let dueDate = cal.date(byAdding: .day, value: offsetDays, to: Date()) {
            let due = cal.startOfDay(for: dueDate)
            let defaultPurpose: String
            switch type {
            case .research: defaultPurpose = "Follow up on research"
            case .followUp: defaultPurpose = "Check progress"
            case .practice: defaultPurpose = "Review practice"
            }
            let ci = WorkCheckIn(
                workID: work.id,
                date: due,
                status: .scheduled,
                purpose: defaultPurpose,
                note: "",
                work: work
            )
            context.insert(ci)
            if work.checkIns == nil { work.checkIns = [] }
            work.checkIns = (work.checkIns ?? []) + [ci]
        }

        try context.save()
        return work
    }

    /// Legacy method: Toggle completion for WorkModel (deprecated)
    @available(*, deprecated, message: "WorkModel is deprecated. Use WorkContract status updates instead.")
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

