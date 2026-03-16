import SwiftUI

// Shared sort options for the students list (used by StudentsView and StudentsViewModel)
enum SortOrder: Hashable {
    case manual
    case alphabetical
    case age
    case birthday
}

// Shared logical filter for the students list (used by StudentsView and StudentsViewModel)
enum StudentsFilter: Hashable {
    case all
    case upper
    case lower
    case presentNow
    case withdrawn

    var title: String {
        switch self {
        case .all:
            return "All"
        case .upper:
            return "Upper"
        case .lower:
            return "Lower"
        case .presentNow:
            return "Present Now"
        case .withdrawn:
            return "Withdrawn"
        }
    }

    var color: Color {
        switch self {
        case .all:
            return .accentColor
        case .upper:
            return Color.pink
        case .lower:
            return Color.blue
        case .presentNow:
            return .green
        case .withdrawn:
            return .gray
        }
    }
}
