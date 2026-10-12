import CoreData
import Foundation
@testable import CosmicDaybook

// Two shortcuts only tests used, moved out of the app with the bug hunt
// 2026-10-12 dead-code sweep. The app builds a removal plan, shows it, then
// applies it; it never reads completion records back by work.

extension WorkDeletionService {
    /// Builds the plan for taking `studentID` off the group containing `work`
    /// and applies it at once.
    @discardableResult
    func remove(
        studentID: UUID,
        from work: CDWorkModel,
        persist: (() -> Bool)? = nil
    ) throws -> WorkRemovalPlan {
        let plan = try removalPlan(for: studentID, from: work)
        try apply(plan, persist: persist)
        return plan
    }
}

extension WorkCompletionService {
    /// Every completion record for `workID`, newest first; only `studentID`'s
    /// when one is given.
    static func records(
        for workID: UUID, studentID: UUID? = nil,
        in context: NSManagedObjectContext
    ) throws -> [CDWorkCompletionRecord] {
        let request = CDFetchRequest(CDWorkCompletionRecord.self)
        if let studentID {
            request.predicate = NSPredicate(
                format: "workID == %@ AND studentID == %@", workID.uuidString, studentID.uuidString
            )
        } else {
            request.predicate = NSPredicate(format: "workID == %@", workID.uuidString)
        }
        request.sortDescriptors = [NSSortDescriptor(key: "completedAt", ascending: false)]
        return try context.fetch(request)
    }
}
