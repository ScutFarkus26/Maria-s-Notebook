import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The ready-to-present backlog is one row per lesson, ordered by the child
/// who has waited longest, under a control whose counts have to add up. These
/// pin the grouping, the order, the long-wait marking and the counts, and the
/// way the flags sit on Ready.
@Suite("Ready-to-present backlog")
struct ReadyBacklogTests {

    private struct Item: Equatable {
        let name: String
        let lessonID: UUID
        let studentIDs: [UUID]
    }

    private func group(_ items: [Item], waits: [UUID: Int], longestWaitFirst: Bool = true)
        -> [BacklogLessonGroup<Item>] {
        ReadyBacklog.groupByLesson(
            items,
            lessonID: \.lessonID,
            studentIDs: \.studentIDs,
            waits: waits,
            longestWaitFirst: longestWaitFirst
        )
    }

    // MARK: - Grouping

    @Test("Several groups of one lesson make one row, keeping their order")
    func groupsShareOneRow() {
        let timeline = UUID(), fractions = UUID()
        let items = [
            Item(name: "timeline 1", lessonID: timeline, studentIDs: [UUID()]),
            Item(name: "fractions", lessonID: fractions, studentIDs: [UUID()]),
            Item(name: "timeline 2", lessonID: timeline, studentIDs: [UUID()]),
            Item(name: "timeline 3", lessonID: timeline, studentIDs: [])
        ]
        let rows = group(items, waits: [:], longestWaitFirst: false)
        #expect(rows.map(\.lessonID) == [timeline, fractions])
        #expect(rows[0].items.map(\.name) == ["timeline 1", "timeline 2", "timeline 3"])
        #expect(rows[1].items.map(\.name) == ["fractions"])
    }

    @Test("Without the wait order, rows keep the order of their first group")
    func ageOrderWithoutWaitSort() {
        let lessons = (0..<4).map { _ in UUID() }
        let child = UUID()
        let items = lessons.map { Item(name: "", lessonID: $0, studentIDs: [child]) }
        let rows = group(items, waits: [child: 30], longestWaitFirst: false)
        #expect(rows.map(\.lessonID) == lessons)
    }

    // MARK: - Longest wait first

    @Test("Rows sort by the longest wait among their children, descending")
    func sortsByLongestWait() {
        let short = UUID(), long = UUID(), never = UUID(), unknown = UUID()
        let waits = [short: 2, long: 15, never: ReadyBacklog.neverTaught]
        let a = UUID(), b = UUID(), c = UUID(), d = UUID()
        let items = [
            Item(name: "a", lessonID: a, studentIDs: [short]),
            Item(name: "b", lessonID: b, studentIDs: [short, long]),
            Item(name: "c", lessonID: c, studentIDs: [unknown]),
            Item(name: "d", lessonID: d, studentIDs: [never])
        ]
        let rows = group(items, waits: waits)
        // Never taught leads; a row with no known wait goes last.
        #expect(rows.map(\.lessonID) == [d, b, a, c])
        #expect(rows.map(\.longestWait) == [ReadyBacklog.neverTaught, 15, 2, nil])
    }

    @Test("A lesson's wait is the longest across all of its groups")
    func waitSpansGroups() {
        let waiting = UUID(), fresh = UUID()
        let multi = UUID(), single = UUID()
        let items = [
            Item(name: "single", lessonID: single, studentIDs: [fresh]),
            Item(name: "multi 1", lessonID: multi, studentIDs: [fresh]),
            Item(name: "multi 2", lessonID: multi, studentIDs: [waiting])
        ]
        let rows = group(items, waits: [waiting: 20, fresh: 1])
        #expect(rows.first?.lessonID == multi)
        #expect(rows.first?.longestWait == 20)
    }

    @Test("Equal waits keep the incoming age order")
    func tiesKeepAgeOrder() {
        let child = UUID()
        let lessons = (0..<12).map { _ in UUID() }
        let items = lessons.map { Item(name: "", lessonID: $0, studentIDs: [child]) }
        #expect(group(items, waits: [child: 9]).map(\.lessonID) == lessons)
    }

    // MARK: - Long-wait chips

    @Test("Long wait starts at the threshold and includes never taught")
    func longWaitThreshold() {
        #expect(!ReadyBacklog.isLongWait(7, threshold: 8))
        #expect(ReadyBacklog.isLongWait(8, threshold: 8))
        #expect(ReadyBacklog.isLongWait(ReadyBacklog.neverTaught, threshold: 8))
        // A negative setting cannot make every child "long-waiting" but zero.
        #expect(ReadyBacklog.isLongWait(0, threshold: -3))
    }

    @Test("The chip says the days, or new for a child never taught")
    func waitBadgeWording() {
        #expect(ReadyBacklog.waitBadge(forDays: 15) == "15")
        #expect(ReadyBacklog.waitBadge(forDays: ReadyBacklog.neverTaught) == "new")
    }

    // MARK: - Counts

    @Test("Counts are rows: distinct lessons, not presentations")
    func lessonCountIsDistinctLessons() {
        let lesson = UUID(), other = UUID()
        let items = [
            Item(name: "", lessonID: lesson, studentIDs: []),
            Item(name: "", lessonID: lesson, studentIDs: []),
            Item(name: "", lessonID: other, studentIDs: [])
        ]
        #expect(ReadyBacklog.lessonCount(items, lessonID: \.lessonID) == 2)
        #expect(ReadyBacklog.lessonCount([Item](), lessonID: \.lessonID) == 0)
    }

    @Test("Each segment counts its own lessons; Ready counts no brewing ones")
    func segmentCountsPartition() throws {
        let context = try CoreDataTestHelpers.makeContext()
        func assignment(_ lessonID: UUID) -> CDLessonAssignment {
            let la = CDLessonAssignment(context: context)
            la.id = UUID()
            la.lessonID = lessonID.uuidString
            return la
        }
        let shared = UUID(), readyOnly = UUID(), brewingOnly = UUID()
        let ready = [assignment(shared), assignment(shared), assignment(readyOnly)]
        let blocked = [assignment(brewingOnly), assignment(brewingOnly)]
        let slices = ReadyToPresentSlices(
            ready: ready, blocked: blocked, overdue: [ready[2]], recentlyMissed: [], followUpCount: 4
        )
        #expect(slices.count(.ready) == 2)
        #expect(slices.count(.waitingForWork) == 1)
        #expect(slices.count(.followUp) == 4)
        #expect(slices.count(.overdue) == 1)
        #expect(slices.count(.recentlyMissed) == 0)
        #expect(slices.visible(for: .ready).count == 3)
        #expect(slices.visible(for: .waitingForWork).count == 2)
        #expect(slices.visible(for: .followUp).isEmpty)
    }

    // MARK: - States and flags

    @Test("A flag keeps Ready lit; the states light themselves")
    func flagsNarrowReady() {
        for flag in PresentationsFilterChip.flags {
            #expect(flag.isFlag)
            #expect(flag.segment == .ready)
        }
        for state in PresentationsFilterChip.segments {
            #expect(!state.isFlag)
            #expect(state.segment == state)
        }
        // Every chip is exactly one of the two.
        #expect(
            Set(PresentationsFilterChip.flags + PresentationsFilterChip.segments)
                == Set(PresentationsFilterChip.allCases)
        )
    }

    @Test("Tapping a flag turns it on; tapping it again returns to Ready")
    func flagToggle() {
        #expect(PresentationsFilterChip.overdue.flagTapped(from: .ready) == .overdue)
        #expect(PresentationsFilterChip.overdue.flagTapped(from: .overdue) == .ready)
        #expect(PresentationsFilterChip.recentlyMissed.flagTapped(from: .overdue) == .recentlyMissed)
        #expect(PresentationsFilterChip.suggestedNext.flagTapped(from: .waitingForWork) == .suggestedNext)
    }

    @Test("The section opens on Ready")
    func defaultsToReady() {
        #expect(PresentationsFilterState().selectedChip == .ready)
    }
}
