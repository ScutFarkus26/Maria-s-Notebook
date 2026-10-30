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
    /// its lesson again as a second pass. That leaves no next lesson to be
    /// ready for, so Ready for Next switches off.
    func represent(_ work: CDWorkModel, context: NSManagedObjectContext) {
        guard apply(.incomplete, to: work, context: context) else { return }
        if let id = work.id {
            representWorkIDs.insert(id)
            readyWorkIDs.remove(id)
        }
        flush()
    }

    /// She's ready to move on (2026-10-30): Complete confirms her on the
    /// lesson (not a mastery mark) and puts the next one in the sequence On
    /// Deck. A switch beside the card's choice: the work's status is left
    /// as it is, and it isn't the card's decision. Refused while Re-present
    /// is chosen, which plans this lesson again instead.
    func setReadyForNext(_ isReady: Bool, for work: CDWorkModel) {
        takeUpStored()
        guard let id = work.id, !(isReady && representWorkIDs.contains(id)) else { return }
        if isReady {
            readyWorkIDs.insert(id)
        } else {
            readyWorkIDs.remove(id)
        }
        flush()
    }

    /// Resting work is open: a status the card set in this meeting is taken
    /// back, and Re-present work with no receipt to take back goes back to
    /// Working, as Clear does (bug hunt 2026-10-09, #10). Work changed since
    /// keeps its status and rests. Ready for Next stays as it is.
    func rest(_ work: CDWorkModel, until date: Date, context: NSManagedObjectContext) {
        takeUpStored()
        let transaction = ContextMutationTransaction(context: context)
        let wasRepresent = work.id.map(representWorkIDs.contains) ?? false
        let takeBack = takeBackEarlierChoice(on: work, context: context)
        if wasRepresent, takeBack == .nothing || takeBack == .unreadable, work.status.isClosed {
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
        representWorkIDs.remove(id)
        closeTokens[id] = nil
        reviewedWorkIDs.insert(id)
        flush()
    }

    /// A report's stage from its card (2026-10-30): set on every linked copy
    /// still open or presented, and the card's decision, as a status choice
    /// is. Presented closes the copies as Finished with a receipt, so another
    /// stage, or Rest, takes the close back; an earlier stage reopens copies
    /// presented before. One save; returns false, with nothing changed or
    /// recorded, when it didn't save.
    @discardableResult
    func setStage(_ stage: Int, of report: CDWorkModel, context: NSManagedObjectContext) -> Bool {
        let applied = apply(to: report, context: context) {
            ReportStages.set(stage: stage, on: ReportStages.movingCopies(of: report, in: context), context: context)
        }
        guard applied else { return false }
        flush()
        return true
    }

    private func apply(_ status: WorkStatus, to work: CDWorkModel, context: NSManagedObjectContext) -> Bool {
        apply(to: work, context: context) {
            work.status == status ? [] : [.init(work: work, status: status)]
        }
    }

    /// One card's choice, saved, without writing the draft: `changes` makes
    /// whatever the choice changes besides the status and returns the
    /// statuses to log. The newest receipt for the work is read from the
    /// stored draft first, in case the choice before this one was made in
    /// another window.
    private func apply(
        to work: CDWorkModel, context: NSManagedObjectContext, changes: () -> [WorkLogService.Entry]
    ) -> Bool {
        takeUpStored()
        let transaction = ContextMutationTransaction(context: context)
        _ = takeBackEarlierChoice(on: work, context: context)
        // A rest this choice ends rides in its receipt, so taking the choice
        // back puts the rest back too (bug hunt 2026-10-10, #15).
        let endedRest = work.isResting ? work.restingUntil : nil
        if endedRest != nil { MeetingReviewService.clearWorkResting(work) }
        let entries = changes()
        var receipt: WorkLogService.Receipt?
        if !entries.isEmpty {
            do {
                receipt = try WorkLogService.log(entries, context: context, saveImmediately: false)
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
        // Another choice replaces a Re-present chosen earlier.
        representWorkIDs.remove(id)
        closeTokens[id] = token.map { [$0] }
        reviewedWorkIDs.insert(id)
        return true
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
