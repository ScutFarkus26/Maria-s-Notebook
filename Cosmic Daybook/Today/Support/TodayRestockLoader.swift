// TodayRestockLoader.swift
// Restock's open needs, for Today's Restock card: the office run and the
// to-order list, with each staple's level. A handful of rows, read in each
// reload; Today reloads when a need changes ("OrderItem" in its inputs).

import CoreData
import Foundation

enum TodayRestockLoader {
    static func digest(in context: NSManagedObjectContext) -> RestockDigest {
        let needs = RestockService.openNeeds(in: context)
        guard !needs.isEmpty else { return .empty }
        let stapleIDs = Set(needs.compactMap(\.supplyID).compactMap(UUID.init(uuidString:)))
        var staples: [CDSupply] = []
        if !stapleIDs.isEmpty {
            let request = CDFetchRequest(CDSupply.self)
            request.predicate = NSPredicate(format: "id IN %@", Array(stapleIDs))
            staples = context.safeFetch(request)
        }
        return RestockDigest.make(needs: needs, levels: RestockDigest.levels(of: staples))
    }
}
