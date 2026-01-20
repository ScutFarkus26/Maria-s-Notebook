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
        ids.map { $0.uuidString }.joined(separator: ",")
    }

    /// Orders the provided unscheduled works according to a stored order. Any works
    /// missing from the stored order are appended in creation-date order.
    static func orderedUnscheduled(from base: [WorkModel], orderRaw: String) -> [WorkModel] {
        let parsed = parse(orderRaw)
        var order = parsed.filter { id in base.contains(where: { $0.id == id }) }

        // Append any missing works by createdAt ascending (older first)
        let missing = base.map(\.id).filter { !order.contains($0) }
        let missingWorks = base.filter { missing.contains($0.id) }.sorted { $0.createdAt < $1.createdAt }
        order.append(contentsOf: missingWorks.map { $0.id })

        let indexMap = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        return base.sorted { (indexMap[$0.id] ?? Int.max) < (indexMap[$1.id] ?? Int.max) }
    }
}

