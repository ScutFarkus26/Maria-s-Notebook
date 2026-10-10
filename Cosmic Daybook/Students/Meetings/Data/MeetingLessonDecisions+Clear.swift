import CoreData
import Foundation

// Clear: the Re-present and Ready for Next work a meeting closed goes back as
// it was before the meeting, and the confirmation names it first.
extension MeetingLessonDecisions {

    /// Puts the Re-present and Ready for Next work in `draft` back as it was
    /// before the meeting, through each card's `WorkLogService` receipt. Work
    /// changed after the meeting is left alone and named in a toast; work
    /// whose receipt can't be read (a draft saved before receipts were kept)
    /// goes back to Working as it always has. One save; nothing is written
    /// when it fails, and it returns false so the caller keeps the draft and
    /// its receipts for another try (bug hunt 2026-10-10, #12).
    @discardableResult
    static func takeBack(_ draft: Draft, context: NSManagedObjectContext) -> Bool {
        let works = pendingWork(in: draft, context: context)
        guard !works.isEmpty else { return true }
        let tokens = draft.closeTokens ?? [:]

        let transaction = ContextMutationTransaction(context: context)
        var reopen: [CDWorkModel] = []
        var leftAlone: [CDWorkModel] = []
        for work in works {
            switch MeetingCloseToken.takeBack(receipts(of: work, in: tokens), of: work, in: context) {
            case .takenBack:
                break
            case .changedSince:
                leftAlone.append(work)
            case .nothing, .unreadable:
                if work.status.isClosed { reopen.append(work) }
            }
        }
        do {
            if !reopen.isEmpty {
                try WorkLogService.log(
                    reopen.map { .init(work: $0, status: .active) }, context: context, saveImmediately: false
                )
            }
            guard context.safeSave() else { throw WorkLogService.LogError.saveFailed }
            transaction.commit()
        } catch {
            transaction.rollback()
            ToastService.shared.showError("Couldn't put the work back to Working. Open it to change it by hand.")
            return false
        }
        if let message = leftAloneMessage(leftAlone, context: context) {
            ToastService.shared.showInfo(message, duration: 4)
        }
        return true
    }

    /// "<Lesson> was changed after the meeting, so it was left as it is."
    static func leftAloneMessage(_ works: [CDWorkModel], context: NSManagedObjectContext) -> String? {
        let names = works.map { lessonName(of: $0, context: context) }
        guard let first = names.first else { return nil }
        guard names.count > 1 else { return "\(first) was changed after the meeting, so it was left as it is." }
        let list = ListFormatter.localizedString(byJoining: names)
        return "\(list) were changed after the meeting, so they were left as they are."
    }

    /// The Re-present and Ready for Next work Clear would change: work whose
    /// receipts it can take back, and closed work it reopens for want of a
    /// receipt. Work changed after the meeting isn't in it; Clear leaves that be.
    static func workClearWouldChange(_ draft: Draft, context: NSManagedObjectContext) -> [CDWorkModel] {
        let tokens = draft.closeTokens ?? [:]
        return pendingWork(in: draft, context: context).filter { work in
            let workReceipts = receipts(of: work, in: tokens)
            guard isReadable(workReceipts, in: context) else { return work.status.isClosed }
            return MeetingCloseToken.canTakeBack(workReceipts, from: work)
        }
    }

    /// "Clear this meeting?"'s message: what's erased, and the work that goes
    /// back to how it was before the meeting (bug hunt 2026-10-10, #14).
    static func clearConfirmation(studentName: String, draft: Draft, context: NSManagedObjectContext) -> String {
        let erased = "Everything written for \(studentName)'s meeting so far will be erased."
        let names = workClearWouldChange(draft, context: context)
            .map { lessonName(of: $0, context: context) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard let first = names.first else { return erased }
        guard names.count > 1 else { return "\(erased) \(first) goes back to how it was before the meeting." }
        let list = ListFormatter.localizedString(byJoining: names)
        return "\(erased) \(list) go back to how they were before the meeting."
    }
}
