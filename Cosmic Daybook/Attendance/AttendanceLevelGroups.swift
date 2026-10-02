import Foundation

/// A roll split into one block per level: Upper Elementary, then
/// Adolescent, then Lower, the order the front-desk email lists them in.
/// Each block keeps the name order on its own. Shared by the notebook's roll
/// and the Daybook Assistant's grid (Group by Level in each).
enum AttendanceLevelGroups {
    struct Group<Item> {
        let level: AttendanceEmailLevel
        let items: [Item]
    }

    /// `items` in level blocks, in their order within each block; empty
    /// levels left out, and a level the report doesn't know counted as Lower.
    static func grouped<Item>(
        _ items: [Item],
        level: (Item) -> CDStudent.Level
    ) -> [Group<Item>] {
        let byLevel = Dictionary(grouping: items) {
            AttendanceEmailLevel(rawValue: level($0).rawValue) ?? .lower
        }
        return AttendanceEmailLevel.allCases.compactMap { block in
            guard let items = byLevel[block], !items.isEmpty else { return nil }
            return Group(level: block, items: items)
        }
    }
}
