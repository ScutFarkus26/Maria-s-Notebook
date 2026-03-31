// WorksInboxOrderStore.swift
// Provides utilities to parse, serialize, and order unscheduled WorkModel instances
// based on a stored comma-separated UUID string.

import Foundation

/// Stores and applies a stable order for unscheduled works using a comma-separated UUID list.
/// All methods are pure helpers. No behavior changes in this refactor.
enum WorksInboxOrderStore {
    // MARK: - Public API
    static func parse(_ raw: String) -> [UUID] {
        raw.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }

    static func serialize(_ ids: [UUID]) -> String {
        ids.map(\.uuidString).joined(separator: ",")
    }

    /// Orders the provided unscheduled works according to a stored order. Any works
    /// missing from the stored order are appended in creation-date order.
    static func orderedUnscheduled(from base: [WorkModel], orderRaw: String) -> [WorkModel] {
        let parsed = parse(orderRaw)
        var order = parsed.filter { id in base.contains(where: { $0.id == id }) }

        // Append any missing works by createdAt ascending (older first)
        let missing = base.compactMap(\.id).filter { !order.contains($0) }
        let missingSet = Set(missing)
        let missingWorks = base.filter { $0.id.map { missingSet.contains($0) } ?? false }.sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        order.append(contentsOf: missingWorks.compactMap(\.id))

        // Use uniquingKeysWith to handle potential duplicates
        let indexMap = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return base.sorted { ($0.id.flatMap { indexMap[$0] } ?? Int.max) < ($1.id.flatMap { indexMap[$0] } ?? Int.max) }
    }
}
