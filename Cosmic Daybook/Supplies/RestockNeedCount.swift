// RestockNeedCount.swift
// How many needs are open, for the Restock row's badge in the Mac and iPad
// sidebars. Counted in the store (no rows fetched), when the sidebar appears
// and whenever a need changes here or arrives from another device.

import SwiftUI
import CoreData

private struct RestockNeedCountTracker: ViewModifier {
    @Binding var count: Int
    let context: NSManagedObjectContext

    func body(content: Content) -> some View {
        content
            .task { recount() }
            .onPresentationDataChange(of: ["OrderItem"], in: context) { _ in recount() }
    }

    private func recount() {
        let counts = RestockService.openNeedCounts(in: context)
        let total = counts.officeRun + counts.toOrder
        if total != count { count = total }
    }
}

extension View {
    /// Keeps `count` at the number of open needs (the office run plus to order).
    func trackingRestockNeedCount(_ count: Binding<Int>, in context: NSManagedObjectContext) -> some View {
        modifier(RestockNeedCountTracker(count: count, context: context))
    }
}
