//
//  InboxOrderStore.swift
//  
//  Provides utilities to parse, serialize, and order unscheduled StudentLesson instances
//  based on a stored comma-separated UUID string.
//

import Foundation

enum InboxOrderStore {
    static func parse(_ raw: String) -> [UUID] {
        raw.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }

    static func serialize(_ ids: [UUID]) -> String {
        ids.uuidStrings.joined(separator: ",")
    }

    static func orderedUnscheduled(from all: [StudentLesson], orderRaw: String) -> [StudentLesson] {
        let base = all.filter { $0.scheduledFor == nil && !$0.isGiven }
        let parsedOrder = parse(orderRaw)
        var order = parsedOrder.filter { id in base.contains(where: { $0.id == id }) }

        let missing = base.map(\.id).filter { !order.contains($0) }
        let missingLessons = base.filter { missing.contains($0.id) }.sorted { $0.createdAt < $1.createdAt }
        order.append(contentsOf: missingLessons.map(\.id))

        // Use uniquingKeysWith to handle potential duplicates
        let indexMap = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return base.sorted {
            (indexMap[$0.id] ?? Int.max) < (indexMap[$1.id] ?? Int.max)
        }
    }
}
