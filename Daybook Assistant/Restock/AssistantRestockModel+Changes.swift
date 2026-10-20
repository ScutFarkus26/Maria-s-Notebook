import Foundation
import CoreData

// Changes the Restock tab turns down or adjusts before they reach
// `RestockService`: a staple that's gone, and "We need…" again for a one-off
// already listed.

extension AssistantRestockModel {

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
        guard need.requestedAt == nil, OrderService.clampedQuantity(quantity) > need.quantity else {
            return .alreadyListed
        }
        RestockService.setQuantity(need, to: quantity, at: now())
        changed()
        return flush() ? .updatedQuantity : .notSaved
    }
}
