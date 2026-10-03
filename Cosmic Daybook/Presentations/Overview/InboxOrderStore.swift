//
//  InboxOrderStore.swift
//
//  Provides utilities to parse, serialize, and order unscheduled CDLessonAssignment instances
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

    static func orderedUnscheduled(from all: [CDLessonAssignment], orderRaw: String) -> [CDLessonAssignment] {
        let base = all.filter { $0.scheduledFor == nil && !$0.isGiven }
        let parsedOrder = parse(orderRaw)
        var order = parsedOrder.filter { id in base.contains(where: { $0.id == id }) }

        let baseIDs = base.compactMap(\.id)
        let missing = baseIDs.filter { !order.contains($0) }
        let missingLessons = base.filter { guard let id = $0.id else { return false }; return missing.contains(id) }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        order.append(contentsOf: missingLessons.compactMap(\.id))

        // Use uniquingKeysWith to handle potential duplicates
        let indexMap = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return base.sorted {
            (indexMap[$0.id ?? UUID()] ?? Int.max) < (indexMap[$1.id ?? UUID()] ?? Int.max)
        }
    }
}
