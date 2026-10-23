// ScheduleLayout.swift
// Where things go on the Schedules page, worked out without a screen: the
// hours the Day view spans, each item's place in its lane (side by side when
// two overlap), the iPhone list's rows, and which item a warning points at.

import CoreGraphics
import Foundation

enum ScheduleGridLayout {

    /// Points per minute down the Day view.
    static let pointsPerMinute: CGFloat = 2
    /// No block is drawn shorter than this (15 minutes), so a 5-minute one can still be read.
    static let minimumBlockHeight: CGFloat = 30
    /// A block drawn shorter than this shows its title and time on one line.
    static let compactBlockHeight: CGFloat = 48
    static let lessonHeight: CGFloat = 32
    static let halfListHeaderHeight: CGFloat = 26
    static let halfListRowHeight: CGFloat = 22

    /// One item, placed in its lane.
    struct Placed: Identifiable, Equatable {
        let item: ScheduleDay.Item
        let top: CGFloat
        let height: CGFloat
        /// Its column among the items it overlaps, from 0.
        var column: Int
        /// How many columns those items share.
        var columns: Int

        var id: String { item.id }
    }

    /// The minutes the Day view spans: whole hours around every item, and
    /// never less than 8:00 to 3:00.
    static func range(of day: ScheduleDay) -> ClosedRange<Int> {
        let items = day.lanes.flatMap(\.items)
        let starts = items.map(\.startMinute)
        let ends = items.map { $0.endMinute ?? ($0.startMinute + 30) }
        let first = min(starts.min() ?? 8 * 60, 8 * 60)
        let last = max(ends.max() ?? 15 * 60, 15 * 60)
        let lower = max(0, (first / 60) * 60)
        let upper = min(24 * 60, ((last + 59) / 60) * 60)
        return lower...max(upper, lower + 60)
    }

    /// The drawn height of an item: a block by its length, a lesson by its
    /// line, a half's list by its rows.
    static func height(of item: ScheduleDay.Item) -> CGFloat {
        switch item.kind {
        case .block(let block), .turn(let block):
            let rows = CGFloat(block.lessons.count) * halfListRowHeight
                + (block.isDayChange ? 16 : 0)
            return max(CGFloat(block.values.lengthMinutes) * pointsPerMinute, minimumBlockHeight + rows)
        case .lesson(let lesson):
            return lessonHeight + (lesson.note == nil ? 0 : 16)
        case .halfList(_, let lessons):
            let notes = lessons.filter { $0.note != nil }.count
            return halfListHeaderHeight + CGFloat(lessons.count) * halfListRowHeight + CGFloat(notes) * 16 + 8
        }
    }

    private static func isHalfList(_ item: ScheduleDay.Item) -> Bool {
        if case .halfList = item.kind { return true }
        return false
    }

    /// How far down the lanes go: the day's hours, or further when an item
    /// was moved down past the last of them.
    static func contentHeight(range: ClosedRange<Int>, placed: [[Placed]]) -> CGFloat {
        let hours = CGFloat(range.upperBound - range.lowerBound) * pointsPerMinute
        let bottom = placed.joined().map { $0.top + $0.height }.max() ?? 0
        return max(hours, bottom)
    }

    static func top(of minute: Int, from start: Int) -> CGFloat {
        CGFloat(minute - start) * pointsPerMinute
    }

    /// Nearer the top first; at the same place, blocks before lessons.
    private static func placedFirst(_ lhs: Placed, _ rhs: Placed) -> Bool {
        if lhs.top != rhs.top { return lhs.top < rhs.top }
        return lhs.item.rank < rhs.item.rank
    }

    /// A lane's items placed from `start`: each at its time, and items that
    /// overlap on screen side by side in columns. A half's list of lessons
    /// has no time of its own, so it moves down past a block or turn already
    /// there (the guide's 9:00 turn) rather than sharing its width.
    static func place(_ items: [ScheduleDay.Item], from start: Int) -> [Placed] {
        var sorted: [Placed] = items.filter { !isHalfList($0) }.map { item in
            Placed(
                item: item, top: top(of: item.startMinute, from: start), height: height(of: item),
                column: 0, columns: 1
            )
        }
        for item in items where isHalfList(item) {
            let height = height(of: item)
            var top = top(of: item.startMinute, from: start)
            while let blocking = sorted.first(where: { $0.top < top + height && top < $0.top + $0.height }) {
                top = blocking.top + blocking.height + 4
            }
            sorted.append(Placed(item: item, top: top, height: height, column: 0, columns: 1))
        }
        sorted.sort(by: placedFirst)
        var result: [Placed] = []
        var cluster: [Placed] = []
        var columnBottoms: [CGFloat] = []
        var clusterBottom: CGFloat = -.infinity

        func closeCluster() {
            let count = max(columnBottoms.count, 1)
            result += cluster.map { placed in
                var placed = placed
                placed.columns = count
                return placed
            }
            cluster = []
            columnBottoms = []
        }

        for var placed in sorted {
            if placed.top >= clusterBottom { closeCluster() }
            if let free = columnBottoms.firstIndex(where: { $0 <= placed.top }) {
                placed.column = free
                columnBottoms[free] = placed.top + placed.height
            } else {
                placed.column = columnBottoms.count
                columnBottoms.append(placed.top + placed.height)
            }
            let bottom: CGFloat = placed.top + placed.height
            clusterBottom = cluster.isEmpty ? bottom : max(clusterBottom, bottom)
            cluster.append(placed)
        }
        closeCluster()
        return result
    }
}

/// The iPhone's Day list and the scroll target for a warning.
enum ScheduleDayRows {

    /// One row: an item and the lane it is in.
    struct Row: Identifiable, Equatable {
        let lane: TimetableLaneSnapshot
        let item: ScheduleDay.Item

        var id: String { "\(lane.id.uuidString)/\(item.id)" }
    }

    /// The day as one list in time order. With every lane, a turn shows once,
    /// as the room's block; filtered to one lane, that lane's items, its
    /// turns among them.
    static func rows(_ day: ScheduleDay, lane filter: UUID? = nil) -> [Row] {
        let order = Dictionary(day.lanes.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        var rows: [Row] = []
        for lane in day.lanes where filter == nil || filter == lane.id {
            for item in lane.items {
                if filter == nil, case .turn = item.kind { continue }
                rows.append(Row(lane: lane.lane, item: item))
            }
        }
        return rows.sorted { lhs, rhs in
            if lhs.item.startMinute != rhs.item.startMinute { return lhs.item.startMinute < rhs.item.startMinute }
            let left = order[lhs.lane.id] ?? 0
            let right = order[rhs.lane.id] ?? 0
            if left != right { return left < right }
            return lhs.item.rank < rhs.item.rank
        }
    }

    /// The row (lane and item) holding one of the guide's lessons: the lesson
    /// itself, its half's list, or the turn it was placed in. The guide's
    /// lane first.
    static func row(holdingLesson id: UUID, in day: ScheduleDay) -> Row? {
        let lanes = day.lanes.sorted { lhs, rhs in lhs.lane.isGuide && !rhs.lane.isGuide }
        for lane in lanes {
            for item in lane.items where holds(item, lesson: id) {
                return Row(lane: lane.lane, item: item)
            }
        }
        return nil
    }

    private static func holds(_ item: ScheduleDay.Item, lesson id: UUID) -> Bool {
        switch item.kind {
        case .lesson(let lesson): lesson.id == id
        case .halfList(_, let lessons): lessons.contains { $0.id == id }
        case .turn(let block), .block(let block): block.lessons.contains { $0.id == id }
        }
    }
}
