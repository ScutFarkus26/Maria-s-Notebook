//
//  ChecklistStudentColumns.swift
//  Cosmic Daybook
//
//  The checklist's student columns on the Mac and iPad: one block per level in the
//  attendance roll's order (Upper, Adolescent, Lower; `AttendanceLevelGroups`), each
//  block keeping the roster's birthday order, with a level band above the names and
//  a heavier rule where one block meets the next.
//

import Foundation

struct ChecklistStudentColumns: Equatable {
    struct Block: Equatable, Identifiable {
        let level: AttendanceEmailLevel
        let count: Int
        var id: String { level.rawValue }
    }

    /// The students in column order.
    private(set) var students: [CDStudent] = []
    /// The level blocks, left to right; their counts add up to `students.count`.
    private(set) var blocks: [Block] = []
    /// The first student of every block after the first: the columns that draw the
    /// heavier rule on their leading edge.
    private(set) var blockStartIDs: Set<UUID> = []

    init() {}

    /// `students` (already in roster order) grouped by level.
    init(students: [CDStudent]) {
        let groups = AttendanceLevelGroups.grouped(students, level: \.level)
        self.students = groups.flatMap(\.items)
        self.blocks = groups.map { Block(level: $0.level, count: $0.items.count) }
        self.blockStartIDs = Set(groups.dropFirst().compactMap { $0.items.first?.id })
    }
}
