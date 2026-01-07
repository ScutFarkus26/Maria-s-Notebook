import Foundation
import SwiftData

@MainActor
struct WorkRepository {
    let context: ModelContext

    // MARK: - Fetch
    
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
    
    /// Fetch WorkModel by ID (primary method)
    func fetchWorkModel(id: UUID) -> WorkModel? {
        let descriptor = FetchDescriptor<WorkModel>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }
    
    /// Legacy method: Fetch WorkContract by ID (deprecated - use fetchWorkModel instead)
    @available(*, deprecated, message: "Use fetchWorkModel(id:) instead. WorkContract is deprecated in favor of WorkModel.")
    func fetchWork(id: UUID) -> WorkContract? {
        let descriptor = FetchDescriptor<WorkContract>(predicate: #Predicate { $0.id == id })
        return (try? context.fetch(descriptor))?.first
    }

    // MARK: - Create (WorkModel)
    /// Create a new WorkModel for a single student
    /// This is the primary work creation method. WorkContract is now read-only for legacy data.
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
            let descriptor = FetchDescriptor<StudentLesson>(
                predicate: #Predicate { sl in
                    sl.lessonID == lessonID.uuidString && sl.studentIDs.contains(studentID.uuidString)
                }
            )
            if let sl = (try? context.fetch(descriptor))?.first {
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
        
        // Create participant for the student
        let participant = WorkParticipantEntity(
            studentID: studentID,
            completedAt: nil,
            work: work
        )
        work.participants = [participant]
        
        context.insert(work)
        try context.save()
        return work
    }
    
    // MARK: - Legacy Create (WorkContract) - Deprecated
    /// Legacy method: Create WorkContract (deprecated in favor of createWork)
    /// WorkContract is now read-only for legacy data. This method now creates WorkModel only.
    /// Returns the created WorkModel wrapped as a legacy-compatible API.
    /// Callers should migrate to use createWork directly.
    @available(*, deprecated, message: "Use createWork instead. WorkContract is deprecated in favor of WorkModel.")
    @discardableResult
    func createWorkContract(
        studentID: UUID,
        lessonID: UUID,
        title: String? = nil,
        kind: WorkKind? = nil,
        presentationID: UUID? = nil,
        scheduledDate: Date? = nil
    ) throws -> WorkModel {
        #if DEBUG
        print("⚠️ createWorkContract called - migrating to WorkModel (call site: \(#file):\(#line))")
        #endif
        // Create and return WorkModel (WorkContract is read-only for legacy data)
        // This method never returns nil - it always returns a WorkModel or throws
        return try createWork(
            studentID: studentID,
            lessonID: lessonID,
            title: title,
            kind: kind,
            presentationID: presentationID,
            scheduledDate: scheduledDate
        )
    }
    
    // MARK: - Update (WorkModel)
    /// Mark a WorkModel as completed
    func markWorkCompleted(id: UUID, outcome: CompletionOutcome? = nil, note: String? = nil) throws {
        guard let work = fetchWorkModel(id: id) else {
            // WorkContract is read-only for legacy data - do not mutate
            #if DEBUG
            if let contract = fetchWork(id: id) {
                print("⚠️ Attempted to mark WorkContract \(id) as completed, but WorkContract is read-only (legacy data)")
            }
            #endif
            // Do not mutate WorkContract - it is read-only
            return
        }
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
        guard let work = fetchWorkModel(id: id) else {
            // WorkContract is read-only for legacy data - do not mutate
            #if DEBUG
            if let contract = fetchWork(id: id) {
                print("⚠️ Attempted to update WorkContract \(id) status, but WorkContract is read-only (legacy data)")
            }
            #endif
            // Do not mutate WorkContract - it is read-only
            return
        }
        work.status = status
        try context.save()
    }
    
    /// Mark a WorkContract as completed (deprecated - use markWorkCompleted)
    @available(*, deprecated, message: "Use markWorkCompleted instead. WorkContract is deprecated in favor of WorkModel.")
    func markContractCompleted(id: UUID, outcome: CompletionOutcome? = nil, note: String? = nil) throws {
        try markWorkCompleted(id: id, outcome: outcome, note: note)
    }
    
    /// Update a WorkContract's status (deprecated - use updateWorkStatus)
    @available(*, deprecated, message: "Use updateWorkStatus instead. WorkContract is deprecated in favor of WorkModel.")
    func updateContractStatus(id: UUID, status: WorkStatus) throws {
        try updateWorkStatus(id: id, status: status)
    }

    // MARK: - Delete (WorkModel)
    func deleteWork(id: UUID) throws {
        // Try WorkModel first
        if let work = fetchWorkModel(id: id) {
            context.delete(work)
            try context.save()
            return
        }
        
        // Fallback: try WorkContract for legacy data (read-only)
        // Inlined fetch to avoid deprecation warning
        let descriptor = FetchDescriptor<WorkContract>(predicate: #Predicate { $0.id == id })
        guard let contract = (try? context.fetch(descriptor))?.first else { return }
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

