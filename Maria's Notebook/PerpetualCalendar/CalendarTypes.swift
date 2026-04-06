import Foundation

// MARK: - Shared Calendar Grid Types

/// Identifies a specific month in the perpetual calendar grid.
struct MonthID: Hashable, Identifiable {
    let year: Int
    let month: Int
    var id: Int { year * 12 + month }
}

/// Identifies a specific day cell in the perpetual calendar grid.
struct CellID: Hashable {
    let year: Int
    let month: Int
    let day: Int
}
