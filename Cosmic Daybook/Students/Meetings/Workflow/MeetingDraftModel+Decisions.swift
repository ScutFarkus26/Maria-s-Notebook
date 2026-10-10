import CoreData
import Foundation

// A work card's outcomes in a meeting. Each applies at once through
// `WorkLogService`, the only status writer, and reaches the stored draft at
// once too, so quitting right after a tap can't leave the work closed with
// no decision to plan or take back (bug hunt 2026-10-10, #16).
extension MeetingDraftModel {

    /// Applies a status from a decision card at once and counts the item as
    /// reviewed. A choice made earlier on the card is taken back first, so
    /// its close doesn't leave skipped check-ins, completed todos or a
    /// completion record behind; work changed since then takes the new
    /// status on top. One save; returns false, with nothing changed or
    /// recorded, when it didn't save.
    @discardableResult
    func decide(_ work: CDWorkModel, status: WorkStatus, context: NSManagedObjectContext) -> Bool {
        guard apply(status, to: work, context: context) else { return false }
        flush()
        return true
    }

    /// The work didn't take: it closes as Incomplete now, and Complete plans
    /// its lesson again as a second pass.
    func represent(_ work: CDWorkModel, context: NSManagedObjectContext) {
        guard apply(.incomplete, to: work, context: context) else { return }
        if let id = work.id { representWorkIDs.insert(id) }
        flush()
    }

    /// She's ready to move on: the work closes with no mastery mark (ready
    /// isn't mastered), and Complete confirms her on the lesson and puts the
    /// next one in the sequence On Deck.
    func readyForNext(_ work: CDWorkModel, context: NSManagedObjectContext) {
        guard apply(.done, to: work, context: context) else { return }
        if let id = work.id { readyWorkIDs.insert(id) }
        flush()
    }

    /// Resting work is open: a status the card set in this meeting is taken
    /// back, and Re-present or Ready work with no receipt to take back goes
    /// back to Working, as Clear does (bug hunt 2026-10-09, #10). Work changed
    /// since keeps its status and rests.
    func rest(_ work: CDWorkModel, until date: Date, context: NSManagedObjectContext) {
        takeUpStored()
        let transaction = ContextMutationTransaction(context: context)
        let wasLessonDecision = work.id.map { representWorkIDs.contains($0) || readyWorkIDs.contains($0) } ?? false
        let takeBack = takeBackEarlierChoice(on: work, context: context)
        if wasLessonDecision, takeBack == .nothing || takeBack == .unreadable, work.status.isClosed {
            do {
                try WorkLogService.log([.init(work: work, status: .active)], context: context, saveImmediately: false)
            } catch {
                transaction.rollback()
                ToastService.shared.showError(Self.decisionFailure)
                return
            }
        }
        MeetingReviewService.setWorkResting(work, until: date)
        work.lastTouchedAt = Date()
        guard context.safeSave() else {
            transaction.rollback()
            ToastService.shared.showError(Self.decisionFailure)
            return
        }
        transaction.commit()
        guard let id = work.id else { return }
        forgetLessonDecision(id)
        closeTokens[id] = nil
        reviewedWorkIDs.insert(id)
        flush()
    }

    /// One card's choice, saved, without writing the draft. The newest
    /// receipt for the work is read from the stored draft first, in case
    /// the choice before this one was made in another window.
    private func apply(_ status: WorkStatus, to work: CDWorkModel, context: NSManagedObjectContext) -> Bool {
        takeUpStored()
        let transaction = ContextMutationTransaction(context: context)
        _ = takeBackEarlierChoice(on: work, context: context)
        // A rest this choice ends rides in its receipt, so taking the choice
        // back puts the rest back too (bug hunt 2026-10-10, #15).
        let endedRest = work.isResting ? work.restingUntil : nil
        if endedRest != nil { MeetingReviewService.clearWorkResting(work) }
        var receipt: WorkLogService.Receipt?
        if work.status != status {
            do {
                receipt = try WorkLogService.log(
                    [.init(work: work, status: status)], context: context, saveImmediately: false
                )
            } catch {
                transaction.rollback()
                ToastService.shared.showError(Self.decisionFailure)
                return false
            }
        }
        work.lastTouchedAt = Date()
        let token = receipt.flatMap {
            MeetingCloseToken($0.token, leaving: work, endingRestUntil: endedRest, in: context)
        }
        guard context.safeSave() else {
            transaction.rollback()
            ToastService.shared.showError(Self.decisionFailure)
            return false
        }
        transaction.commit()
        guard let id = work.id else { return true }
        forgetLessonDecision(id)
        closeTokens[id] = token.map { [$0] }
        reviewedWorkIDs.insert(id)
        return true
    }

    /// Another outcome replaces a Re-present or Ready for Next chosen earlier.
    private func forgetLessonDecision(_ id: UUID) {
        representWorkIDs.remove(id)
        readyWorkIDs.remove(id)
    }

    /// Takes back, in memory, the statuses the card's earlier choices set in
    /// this meeting, newest first (the caller saves).
    private func takeBackEarlierChoice(
        on work: CDWorkModel, context: NSManagedObjectContext
    ) -> MeetingCloseToken.TakeBack {
        guard let id = work.id else { return .nothing }
        return MeetingCloseToken.takeBack(closeTokens[id] ?? [], of: work, in: context)
    }

    /// A decision card that didn't save says so; `safeSave` has logged why.
    private static let decisionFailure = "Couldn't save that decision about the work. Try again."
}
