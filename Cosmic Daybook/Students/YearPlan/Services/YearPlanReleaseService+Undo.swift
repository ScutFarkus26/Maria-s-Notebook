import CoreData
import Foundation

// Just Presented's Undo has to put back what the recording's release changed:
// a child trimmed off another group, a group discarded because she was the
// last one on it, and the entries that pointed at them.

/// The plans and entries a release is about to change, captured before it
/// runs (`YearPlanReleaseService.preimage(after:in:)`).
struct YearPlanReleasePreimage {
    struct Plan {
        let objectID: NSManagedObjectID
        let id: UUID?
        let snapshot: ManagedObjectSnapshot?
        let studentIDs: [String]
        let confirmedStudentIDs: [String]
        let modifiedAt: Date?
    }

    struct Entry {
        let objectID: NSManagedObjectID
        let statusRaw: String
        let promotedAssignmentID: String?
    }

    var plans: [Plan] = []
    var entries: [Entry] = []

    /// Only what differs from `context` now — what the release changed.
    func changed(in context: NSManagedObjectContext) -> YearPlanReleasePreimage {
        YearPlanReleasePreimage(
            plans: plans.filter { plan in
                guard let current = context.existing(CDLessonAssignment.self, plan.objectID),
                      !current.isDeleted else { return true }
                return current.studentIDs != plan.studentIDs
                    || current.confirmedStudentIDs != plan.confirmedStudentIDs
            },
            entries: entries.filter { entry in
                guard let current = context.existing(CDYearPlanEntry.self, entry.objectID) else { return false }
                return current.statusRaw != entry.statusRaw
                    || current.promotedAssignmentID != entry.promotedAssignmentID
            }
        )
    }

    /// Puts trimmed rosters back, recreates discarded plans (same id, their
    /// notes with them), and restores the entries. Does not save.
    func restore(in context: NSManagedObjectContext) {
        for plan in plans {
            if let current = context.existing(CDLessonAssignment.self, plan.objectID), !current.isDeleted {
                current.studentIDs = plan.studentIDs
                current.confirmedStudentIDs = plan.confirmedStudentIDs
                current.modifiedAt = plan.modifiedAt
            } else if plan.id.flatMap({ context.object(CDLessonAssignment.self, id: $0) }) == nil {
                plan.snapshot?.recreate(in: context)
            }
        }
        for entry in entries {
            guard let current = context.existing(CDYearPlanEntry.self, entry.objectID),
                  !current.isDeleted else { continue }
            current.statusRaw = entry.statusRaw
            current.promotedAssignmentID = entry.promotedAssignmentID
        }
    }
}

extension YearPlanReleaseService {

    /// What `releaseRedundantPlans(after:in:)` would touch for `assignment`:
    /// every pending plan its children's entries are promoted into, and every
    /// entry promoted into those plans.
    static func preimage(
        after assignment: CDLessonAssignment, in context: NSManagedObjectContext
    ) -> YearPlanReleasePreimage {
        guard !assignment.lessonID.isEmpty else { return YearPlanReleasePreimage() }
        let assignmentID = assignment.id?.uuidString
        let planIDs = Set(
            promotedEntries(lessonID: assignment.lessonID, studentIDs: assignment.studentIDs, in: context)
                .compactMap(\.promotedAssignmentID)
                .filter { $0 != assignmentID }
        )
        var preimage = YearPlanReleasePreimage()
        for planID in planIDs {
            guard let uuid = UUID(uuidString: planID),
                  let plan = context.object(CDLessonAssignment.self, id: uuid),
                  !plan.isPresented else { continue }
            preimage.plans.append(YearPlanReleasePreimage.Plan(
                objectID: plan.objectID,
                id: plan.id,
                snapshot: ManagedObjectSnapshot(plan),
                studentIDs: plan.studentIDs,
                confirmedStudentIDs: plan.confirmedStudentIDs,
                modifiedAt: plan.modifiedAt
            ))
            for entry in PresentationRecordCleanup.entries(promotedInto: planID, in: context) {
                preimage.entries.append(YearPlanReleasePreimage.Entry(
                    objectID: entry.objectID,
                    statusRaw: entry.statusRaw,
                    promotedAssignmentID: entry.promotedAssignmentID
                ))
            }
        }
        return preimage
    }
}
