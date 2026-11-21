// ClassGridEngine+Staleness.swift
// Which of her work rows a cell reads, and when that work counts as stale: the
// cell's "needs a check-in" dot.

import CoreData
import Foundation

@MainActor
extension ClassGridEngine {
    /// Whether a cell's open work has gone quiet, by the one clock every
    /// screen reads (`WorkNeglect`): `AgingPolicy.staleDays` school days
    /// since its latest touch, a check-in, a practice, a note or the end of a
    /// rest among them, and never while it rests. The dot used to count 14
    /// weekdays from `lastTouchedAt` alone, holidays included, so work
    /// practiced yesterday could carry it (domain logic review 2026-11-20,
    /// R13).
    static func isStale(_ work: CDWorkModel?, today: Date) -> Bool {
        guard let work, work.status.isOpen, let context = work.managedObjectContext else { return false }
        return WorkNeglect.hasGoneQuiet(work, for: AgingPolicy.staleDays, using: context, asOf: today)
    }

    /// The one work row a cell reads its rung and staleness from: open work (Working or
    /// Needs Review) over closed, then the most recently touched. The fetch has no order,
    /// so taking `.first` let an old closed row hide new practice depending on the store.
    static func cellWork(_ works: [CDWorkModel]) -> CDWorkModel? {
        works.max { lhs, rhs in
            if lhs.status.isClosed != rhs.status.isClosed { return lhs.status.isClosed }
            let lhsDate = lastActivity(lhs), rhsDate = lastActivity(rhs)
            if lhsDate != rhsDate { return lhsDate < rhsDate }
            return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
        }
    }

    private static func lastActivity(_ work: CDWorkModel) -> Date {
        work.lastTouchedAt ?? work.completedAt ?? work.createdAt ?? .distantPast
    }
}
