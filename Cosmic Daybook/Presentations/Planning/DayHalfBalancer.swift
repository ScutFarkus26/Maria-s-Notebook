// DayHalfBalancer.swift
// Rearranging a day so no child is called twice in the same half of it.
//
// Two presentations that share a child cannot sit in the same half, and there
// are exactly two halves — which makes this graph two-colouring: a node per
// presentation, an edge wherever two of them share a child, morning and
// afternoon as the colours. So the answer is not always yes. Three lessons that
// pairwise share children form an odd cycle, and no arrangement of two halves
// separates them; a child on three lessons in one day is the same wall reached
// sooner.
//
// That is why `balanced` reports what it could not fix instead of promising a
// clean day. The button that calls it has to be able to say "moved two, and
// Tzofia is still doubled up" — a silent Fix would be lying about every day two
// halves cannot save.
//
// Where a day *is* two-colourable, each connected run of lessons has exactly
// two valid arrangements — the colouring and its mirror — and the one picked is
// the one closest to what the guide already had. Fewest cards moved wins; ties
// go to the evener day, then to moving the later lessons, so a morning that was
// built on purpose stays put and the afternoon absorbs the change.
//
// Nothing here touches Core Data, so the whole gesture is testable without a
// store — see DayBalanceTests.

import Foundation

enum DayHalfBalancer {
    /// One presentation as the balancer sees it: which record, the half it is
    /// in now, and the children called to it.
    struct Booking: Equatable, Sendable {
        let id: UUID
        var period: DayPeriod
        var studentIDs: Set<UUID>
    }

    /// A rearranged day, and an honest account of what is left over.
    struct Outcome: Equatable, Sendable {
        /// The whole day in draw order, unmoved cards included — `DayHalfPlanner
        /// .times` numbers a half by position in this list, so the ones that
        /// stayed still have to be in it.
        let placements: [DayHalfPlanner.Placement]
        let movedToMorning: Set<UUID>
        let movedToAfternoon: Set<UUID>
        /// Children still called twice in one half, by the half they clash in.
        let unresolved: [DayPeriod: Set<UUID>]

        var movedCount: Int { movedToMorning.count + movedToAfternoon.count }

        var unresolvedStudentIDs: Set<UUID> {
            unresolved.values.reduce(into: Set<UUID>()) { $0.formUnion($1) }
        }
    }

    /// Children called to two or more presentations in the same half.
    ///
    /// Keyed by half rather than flattened into one set for the day, because a
    /// child doubled up in the morning is not doubled up in the afternoon — and
    /// the card that draws the warning ring only ever sits in one of them.
    static func clashes(in bookings: [Booking]) -> [DayPeriod: Set<UUID>] {
        var counts: [DayPeriod: [UUID: Int]] = [:]
        for booking in bookings {
            for student in booking.studentIDs {
                counts[booking.period, default: [:]][student, default: 0] += 1
            }
        }
        return counts.mapValues { Set($0.filter { $0.value >= 2 }.keys) }
    }

    /// The day rearranged to clear every clash two halves can clear.
    static func balanced(_ bookings: [Booking]) -> Outcome {
        let neighbours = adjacency(bookings)
        var periods = bookings.map(\.period)
        for run in runs(sharing: neighbours) {
            if let sides = run.sides {
                periods = bestMirror(of: run.members, sides: sides, current: periods)
            } else {
                periods = locallyImproved(
                    run.members,
                    neighbours: neighbours,
                    bookings: bookings,
                    periods: periods
                )
            }
        }
        return outcome(from: bookings, settledInto: periods)
    }

    // MARK: - The graph

    /// Which presentations share a child with which, as sorted neighbour lists.
    ///
    /// Sorted so the whole rearrangement is reproducible: the same day balances
    /// the same way every time, whatever order the dictionary enumerated in.
    private static func adjacency(_ bookings: [Booking]) -> [[Int]] {
        var byStudent: [UUID: [Int]] = [:]
        for (index, booking) in bookings.enumerated() {
            for student in booking.studentIDs {
                byStudent[student, default: []].append(index)
            }
        }
        var shared = [Set<Int>](repeating: [], count: bookings.count)
        for group in byStudent.values where group.count > 1 {
            for index in group {
                shared[index].formUnion(group.lazy.filter { $0 != index })
            }
        }
        return shared.map { $0.sorted() }
    }

    /// One connected run of presentations that share children. Lessons in
    /// different runs never constrain each other, so each is solved on its own
    /// and a day with no shared children is a day of runs of one.
    private struct Run {
        /// Members in draw order.
        let members: [Int]
        /// Which side of the run each member falls on — nil when the run cannot
        /// be split in two at all, which is the odd cycle two halves have no
        /// answer for.
        let sides: [Int: Bool]?
    }

    private static func runs(sharing neighbours: [[Int]]) -> [Run] {
        var visited = [Bool](repeating: false, count: neighbours.count)
        var result: [Run] = []
        for start in neighbours.indices where !visited[start] {
            var sides: [Int: Bool] = [start: false]
            var queue = [start]
            var head = 0
            var splittable = true
            visited[start] = true
            while head < queue.count {
                let node = queue[head]
                head += 1
                let side = sides[node] ?? false
                for next in neighbours[node] {
                    if let taken = sides[next] {
                        // Two lessons that share a child landed on the same
                        // side. Nothing further along can undo that.
                        if taken == side { splittable = false }
                    } else {
                        sides[next] = !side
                    }
                    if !visited[next] {
                        visited[next] = true
                        queue.append(next)
                    }
                }
            }
            result.append(Run(members: queue.sorted(), sides: splittable ? sides : nil))
        }
        return result
    }

    // MARK: - Choosing between the two arrangements

    /// A splittable run has exactly two arrangements — the colouring and its
    /// mirror. This picks whichever disturbs the guide's day least.
    private static func bestMirror(
        of members: [Int],
        sides: [Int: Bool],
        current: [DayPeriod]
    ) -> [DayPeriod] {
        let mirrors = [false, true].map { flipped -> [DayPeriod] in
            var periods = current
            for member in members {
                periods[member] = (sides[member] ?? false) == flipped ? .morning : .afternoon
            }
            return periods
        }
        return mirrors.min {
            churn(of: $0, members: members, from: current)
                < churn(of: $1, members: members, from: current)
        } ?? current
    }

    /// How much an arrangement disturbs the day the guide already built.
    ///
    /// Lower is better, read in order: fewest cards moved, then the evener day,
    /// then the arrangement that leaves the earlier lessons alone — a guide
    /// coming back to a rearranged day should find its opening where he left
    /// it, with the change further down.
    private struct Churn: Comparable {
        let moves: Int
        let imbalance: Int
        /// Negated sum of the moved cards' positions, so "moves the later
        /// lessons" sorts as the better answer.
        let earliness: Int

        static func < (lhs: Churn, rhs: Churn) -> Bool {
            if lhs.moves != rhs.moves { return lhs.moves < rhs.moves }
            if lhs.imbalance != rhs.imbalance { return lhs.imbalance < rhs.imbalance }
            return lhs.earliness < rhs.earliness
        }
    }

    private static func churn(
        of candidate: [DayPeriod],
        members: [Int],
        from current: [DayPeriod]
    ) -> Churn {
        let moved = members.filter { candidate[$0] != current[$0] }
        return Churn(
            moves: moved.count,
            imbalance: imbalance(candidate),
            earliness: -moved.reduce(0, +)
        )
    }

    private static func imbalance(_ periods: [DayPeriod]) -> Int {
        let morning = periods.filter { $0 == .morning }.count
        return abs(morning - (periods.count - morning))
    }

    // MARK: - Best effort where two halves are not enough

    /// The fallback for a run two halves cannot separate.
    ///
    /// It starts from the arrangement the guide already has and flips one card
    /// at a time, keeping only flips that strictly reduce the number of
    /// doubled-up children — so a day that cannot be made clean is at least
    /// made cleaner, and cards that were never part of the problem stay where
    /// they were put. Every accepted flip lowers a count that cannot go below
    /// zero, so the loop ends.
    private static func locallyImproved(
        _ members: [Int],
        neighbours: [[Int]],
        bookings: [Booking],
        periods: [DayPeriod]
    ) -> [DayPeriod] {
        var periods = periods
        var improving = true
        while improving {
            improving = false
            for member in members {
                let before = clashCost(at: member, neighbours: neighbours, bookings: bookings, periods: periods)
                periods[member] = flipped(periods[member])
                let after = clashCost(at: member, neighbours: neighbours, bookings: bookings, periods: periods)
                if after < before {
                    improving = true
                } else {
                    periods[member] = flipped(periods[member])
                }
            }
        }
        return periods
    }

    private static func flipped(_ period: DayPeriod) -> DayPeriod {
        period == .morning ? .afternoon : .morning
    }

    /// How many child-and-half collisions this one card is party to. Flipping a
    /// card only changes the edges touching it, so this local count is the
    /// whole of what one flip can improve.
    private static func clashCost(
        at node: Int,
        neighbours: [[Int]],
        bookings: [Booking],
        periods: [DayPeriod]
    ) -> Int {
        neighbours[node].reduce(0) { total, other in
            guard periods[other] == periods[node] else { return total }
            return total + bookings[node].studentIDs.intersection(bookings[other].studentIDs).count
        }
    }

    // MARK: - Reporting

    /// Cards keep their place in the day's list, so a lesson crossing the seam
    /// keeps its relative position among the lessons it joins rather than
    /// jumping to the end of them. The day changes halves, not shape.
    private static func outcome(from bookings: [Booking], settledInto periods: [DayPeriod]) -> Outcome {
        var settled: [Booking] = []
        var toMorning: Set<UUID> = []
        var toAfternoon: Set<UUID> = []
        for (index, booking) in bookings.enumerated() {
            var moved = booking
            moved.period = periods[index]
            settled.append(moved)
            guard moved.period != booking.period else { continue }
            if moved.period == .morning {
                toMorning.insert(booking.id)
            } else {
                toAfternoon.insert(booking.id)
            }
        }
        return Outcome(
            placements: settled.map { DayHalfPlanner.Placement(id: $0.id, period: $0.period) },
            movedToMorning: toMorning,
            movedToAfternoon: toAfternoon,
            unresolved: clashes(in: settled)
        )
    }
}
