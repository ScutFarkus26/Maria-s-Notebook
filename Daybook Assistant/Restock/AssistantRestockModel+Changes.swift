import Foundation
import CoreData

// Changes the Restock tab turns down or adjusts before they reach
// `RestockService`: any while the share is View only, a staple that's gone,
// and "We need…" again for a one-off already listed.

extension AssistantRestockModel {

    /// Whether a change may be made now: never while the share is View only
    /// (bug hunt 2026-11-02 #29), whose saves would never reach the guide.
    /// Notes a View only share that arrived since the last load, so the tab
    /// says so at once.
    func mayChange() -> Bool {
        let readOnly = readOnlyNow()
        if isViewOnly != readOnly { isViewOnly = readOnly }
        return !readOnly
    }

    /// The permission matrix the attendance store goes by: an assistant
    /// writes Restock, except while the share is View only.
    static var refusedByShare: Bool {
        !ClassroomPermissions.canWrite(entityName: "Supply", role: .assistant)
    }

    /// Whether `staple` is gone (`isGone`), reloading the shelf without it
    /// when it is. A level set on a staple the guide had just deleted opened
    /// a need for nothing, left on the office run (bug hunt 2026-10-20, #30).
    func stapleIsGone(_ staple: CDSupply) -> Bool {
        guard Self.isGone(staple) else { return false }
        load(reconcile: false)
        return true
    }

    /// "We need…" again for a one-off already listed: asked for more than it
    /// says, it says the larger count, while the guide hasn't asked the
    /// office for it. It used to keep the old count (bug hunt 2026-10-20, #33).
    func raiseQuantity(of need: CDOrderItem, to quantity: Int) -> AddResult {
        guard mayChange() else { return .nothing }
        guard need.requestedAt == nil, OrderService.clampedQuantity(quantity) > need.quantity else {
            return .alreadyListed
        }
        RestockService.setQuantity(need, to: quantity, at: now())
        changed()
        return flush() ? .updatedQuantity : .notSaved
    }
}
