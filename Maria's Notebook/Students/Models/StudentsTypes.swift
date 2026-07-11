import SwiftUI
import CoreData

// Shared sort options for the students list (used by StudentsView and StudentsViewModel)
enum SortOrder: Hashable {
    case manual
    case alphabetical
    case age
    case birthday
}

// View style for the students roster detail area (list+detail vs. card grid browser)
enum StudentsViewStyle: String {
    case list
    case grid
    case table
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

    /// Short label used by the scope chips above the roster list.
    var chipTitle: String {
        switch self {
        case .presentNow:
            return "Here"
        default:
            return title
        }
    }

    /// Raw value persisted in AppStorage for the roster filter.
    var storageValue: String {
        switch self {
        case .all: return "all"
        case .upper: return "upper"
        case .lower: return "lower"
        case .presentNow: return "presentNow"
        case .withdrawn: return "withdrawn"
        }
    }
}
