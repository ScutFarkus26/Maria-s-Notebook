import Foundation
import SwiftData

extension WorkModel {
    /// Create a WorkModel from a WorkContract.
    /// This mapping helper enables dual-write during migration.
    /// - Parameters:
    ///   - contract: The WorkContract to map from
    ///   - context: The ModelContext to use for relationship lookups
    /// - Returns: A new WorkModel instance with fields mapped from the contract
    static func from(
        contract: WorkContract,
        in context: ModelContext
    ) -> WorkModel {
        // Map basic fields
        let studentID = UUID(uuidString: contract.studentID)
        let lessonID = UUID(uuidString: contract.lessonID)
        let presentationID = contract.presentationID.flatMap(UUID.init(uuidString:))
        
        // Map WorkKind to WorkType (approximate mapping)
        let workType: WorkType = {
            if let kind = contract.kind {
                switch kind {
                case .practiceLesson:
                    return .practice
                case .followUpAssignment:
                    return .followUp
                case .research:
                    return .research
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
        
        // If presentationID is not available but we have studentID and lessonID,
        // try to find the StudentLesson
        if studentLessonID == nil, let sid = studentID, let lid = lessonID {
            // Fetch candidates by lessonID (studentIDs is @Transient and can't be queried in SwiftData)
            let descriptor = FetchDescriptor<StudentLesson>(
                predicate: #Predicate { sl in
                    sl.lessonID == lid.uuidString
                }
            )
            // Filter in memory using the computed studentIDs property
            if let sl = (try? context.fetch(descriptor))?.first(where: { $0.studentIDs.contains(sid.uuidString) }) {
                studentLessonID = sl.id
            }
        }
        
        // Create WorkModel with mapped fields
        let work = WorkModel(
            id: UUID(), // New ID (don't reuse contract.id to avoid conflicts)
            title: contract.title ?? "",
            workType: workType,
            studentLessonID: studentLessonID,
            notes: contract.completionNote ?? "",
            createdAt: contract.createdAt,
            completedAt: contract.completedAt,
            participants: [],
            // Migration-ready fields
            kind: contract.kind,
            status: contract.status,
            assignedAt: contract.createdAt, // Use createdAt as assignedAt
            lastTouchedAt: nil, // Will be computed by aging policy
            dueAt: contract.scheduledDate,
            completionOutcome: contract.completionOutcome,
            legacyContractID: contract.id
        )
        
        // Create participant for the student
        if let sid = studentID {
            let participant = WorkParticipantEntity(
                studentID: sid,
                completedAt: contract.completedAt, // If contract is completed, participant is too
                work: work
            )
            work.participants = [participant]
        }
        
        // Ensure identity fields are always populated
        if let sid = studentID {
            work.studentID = sid.uuidString
        }
        if let lid = lessonID {
            work.lessonID = lid.uuidString
        }
        work.legacyStudentLessonID = studentLessonID?.uuidString
        
        return work
    }
}

