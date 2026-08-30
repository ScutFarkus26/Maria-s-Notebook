import Foundation
import Testing
@testable import Maria_s_Notebook

/// Structural tests for `TriageSplit`, the container behind the workspace's
/// three lists.
///
/// `LessonsAndWorkTriageTests` pins *where* one record goes. These pin that
/// splitting a whole set keeps the promise the three lists make: every record
/// lands in exactly one list, nothing is dropped, nothing is shown twice, and
/// the rule is consulted once per record rather than once per reader.
///
/// Nothing here touches Core Data — the split is generic precisely so this
/// guarantee can be checked on plain values.
@Suite("Lessons & Work Partition")
struct LessonsAndWorkPartitionTests {

    /// A stub rule that cycles through all four buckets, so every list is
    /// exercised without depending on the real rule's thresholds.
    private func cycling(_ index: Int) -> TriageBucket {
        TriageBucket.allCases[index % TriageBucket.allCases.count]
    }

    // MARK: - Totality and disjointness

    @Test("Every record lands in exactly one list")
    func splitIsTotalAndDisjoint() {
        let records = Array(0..<40)
        let split = TriageSplit(records, bucket: cycling)

        let placed = split.attention + split.scheduled + split.toSchedule + split.done
        #expect(placed.count == records.count, "a record was dropped or duplicated")
        #expect(Set(placed) == Set(records), "the split changed which records are present")

        for record in records {
            let lists = TriageBucket.allCases.filter { split[$0].contains(record) }
            #expect(lists.count == 1, "record \(record) appeared in \(lists.count) lists")
        }
    }

    @Test("An empty input produces four empty lists")
    func emptyInput() {
        let split = TriageSplit([Int](), bucket: cycling)
        for bucket in TriageBucket.allCases {
            #expect(split[bucket].isEmpty)
        }
        #expect(split.workspaceCount == 0)
    }

    @Test("The convenience empty split is empty")
    func emptyInitIsEmpty() {
        let split = TriageSplit<Int>()
        #expect(split.workspaceCount == 0)
        #expect(split.done.isEmpty)
    }

    // MARK: - The memoisation guarantee

    @Test("The rule is asked exactly once per record")
    func ruleIsCalledOncePerRecord() {
        var calls: [Int] = []
        let records = Array(0..<25)

        let split = TriageSplit(records) { record in
            calls.append(record)
            return cycling(record)
        }

        #expect(calls.count == records.count)
        #expect(calls == records, "the rule ran out of order or more than once per record")
        // Reading the split again must not re-run anything.
        _ = split.workspaceCount
        _ = split[.attention]
        #expect(calls.count == records.count, "reading the split re-ran the rule")
    }

    // MARK: - Order

    @Test("Input order survives inside each list")
    func orderIsStable() {
        // Two buckets only, so each list has a long, checkable run.
        let records = Array(0..<20)
        let split = TriageSplit(records) { $0.isMultiple(of: 2) ? .attention : .toSchedule }

        #expect(split.attention == records.filter { $0.isMultiple(of: 2) })
        #expect(split.toSchedule == records.filter { !$0.isMultiple(of: 2) })
    }

    // MARK: - What the workspace counts

    @Test("workspaceCount excludes finished records")
    func workspaceCountExcludesDone() {
        let split = TriageSplit(Array(0..<12), bucket: cycling)

        #expect(split.workspaceCount == split.attention.count
            + split.scheduled.count
            + split.toSchedule.count)
        #expect(!split.done.isEmpty, "the fixture should place something in done")
        #expect(split.workspaceCount == 12 - split.done.count)
    }

    @Test("The subscript agrees with the named lists")
    func subscriptMatchesProperties() {
        let split = TriageSplit(Array(0..<16), bucket: cycling)

        #expect(split[.attention] == split.attention)
        #expect(split[.scheduled] == split.scheduled)
        #expect(split[.toSchedule] == split.toSchedule)
        #expect(split[.done] == split.done)
    }

    // MARK: - Against the real rule

    @Test("A mixed screenful splits the way the rule says it should")
    func realRuleAgreesWithTheSplit() {
        let today = AppCalendar.startOfDay(
            AppCalendar.shared.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        )
        let yesterday = AppCalendar.shared.date(byAdding: .day, value: -1, to: today)!
        let nextWeek = AppCalendar.shared.date(byAdding: .day, value: 7, to: today)!

        let inputs: [WorkTriageInput] = [
            WorkTriageInput(status: .review),                                  // attention
            WorkTriageInput(status: .active, dueAt: yesterday),                // attention
            WorkTriageInput(status: .active, schoolDaysSinceLastTouch: 12),    // attention
            WorkTriageInput(status: .active, dueAt: nextWeek),                 // scheduled
            WorkTriageInput(status: .active, restingUntil: nextWeek),          // scheduled
            WorkTriageInput(status: .active),                                  // toSchedule
            WorkTriageInput(status: .complete)                                 // done
        ]

        let split = TriageSplit(inputs) { LessonsAndWorkTriage.bucket(for: $0, asOf: today) }

        #expect(split.attention.count == 3)
        #expect(split.scheduled.count == 2)
        #expect(split.toSchedule.count == 1)
        #expect(split.done.count == 1)
        #expect(split.workspaceCount == 6)

        // The whole point: what the split says matches asking the rule directly.
        for bucket in TriageBucket.allCases {
            for input in split[bucket] {
                #expect(LessonsAndWorkTriage.bucket(for: input, asOf: today) == bucket)
            }
        }
    }
}
