import Foundation

/// Which way the alphabet runs through the grid, chosen in the Classroom
/// sheet: along each row (Ari, Ben, Cal across the top), or down each column
/// (Ari, Ben, Cal down the left side), the way a printed class list reads.
/// Only on this iPhone.
enum AssistantGridOrder: String, CaseIterable, Identifiable {
    case across
    case down

    static let key = "Assistant.gridOrder"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .across: return "Across"
        case .down: return "Down"
        }
    }

    static func resolved(_ raw: String) -> AssistantGridOrder {
        AssistantGridOrder(rawValue: raw) ?? .across
    }

    /// `items` (already alphabetical) in the order a row-by-row grid of
    /// `columns` lays them out, so they read this way.
    ///
    /// Down fills the columns top to bottom, the first ones a child longer
    /// when the class doesn't divide evenly (22 in three columns: 8, 7, 7),
    /// so the only gaps are at the end of the last row, as they are across.
    func arranged<T>(_ items: [T], columns: Int) -> [T] {
        guard self == .down, columns > 1, items.count > columns else { return items }
        let count = items.count
        let rows = (count + columns - 1) / columns
        // Columns before `longColumns` hold `rows` children; the rest one fewer.
        let longColumns = count % columns == 0 ? columns : count % columns
        var result: [T] = []
        result.reserveCapacity(count)
        for row in 0..<rows {
            for column in 0..<columns {
                guard row < rows - 1 || column < longColumns else { break }
                let start = column * (rows - 1) + min(column, longColumns)
                result.append(items[start + row])
            }
        }
        return result
    }
}
