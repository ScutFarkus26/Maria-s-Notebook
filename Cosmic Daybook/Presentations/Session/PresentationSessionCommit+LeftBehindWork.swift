// PresentationSessionCommit+LeftBehindWork.swift
// A decision that moves off Practice or Follow-up takes back the work the
// earlier decision gave, as long as nobody has used it yet.
//
// One-click Presented applies Practice, and the guide may open Details to
// say Keep watching, Re-present or Follow-up instead. Without this the old
// work stayed open: the child kept practice she was no longer given, a second
// work item joined it, and How It Went read the open work back as Practice.

import CoreData
import Foundation

extension PresentationSessionCommit {

    /// Work this presentation gave a child under a decision she no longer
    /// has, still untouched: open and not turned in, hers alone, with no
    /// check-in done or skipped, no note, no step, no completion, meeting or
    /// practice session. Work with any of that is left as it is; it is part
    /// of her record now, and the guide closes it from the work itself.
    static func untouchedWork(
        leftBehindBy decisions: [UUID: CaptureFollowUp],
        presentationID: UUID,
        context: NSManagedObjectContext
    ) -> [CDWorkModel] {
        guard !decisions.isEmpty else { return [] }
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "presentationID == %@", presentationID.uuidString)
        let candidates = context.safeFetch(request).filter { work in
            guard !work.isDeleted, work.status == .active,
                  let studentID = UUID(uuidString: work.studentID),
                  let decision = decisions[studentID],
                  let kind = work.kind, kind == .practiceLesson || kind == .followUpAssignment,
                  kind != decision.workKind else { return false }
            return WorkGrouping.studentIDs(of: work) == [studentID]
        }
        guard !candidates.isEmpty else { return [] }

        let service = WorkDeletionService(context: context)
        return candidates.filter { work in
            // Practice logged on the work is a completed check-in, so it
            // counts as used here.
            let used = WorkDeletionService.checkIns(of: work, in: context).contains { $0.status != .scheduled }
            let cascade = service.cascade(for: work)
            return !used && cascade.observations == 0 && cascade.steps == 0
                && cascade.completionRecords == 0 && cascade.meetingReviews == 0
                && cascade.scheduledMeetings == 0
        }
    }
}

private extension CaptureFollowUp {
    /// The kind of work the decision gives, if any.
    var workKind: WorkKind? {
        switch self {
        case .practice: .practiceLesson
        case .followUpWork: .followUpAssignment
        default: nil
        }
    }
}
