import SwiftUI
import CoreData

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
    case adolescent
    case presentNow
    /// Due for a lesson: never given one, or `RosterSignalRules.dueSchoolDays`
    /// or more school days since the last.
    case dueForLesson
    case withdrawn

    var title: String {
        switch self {
        case .all:
            return "All"
        case .upper:
            return "Upper"
        case .lower:
            return "Lower"
        case .adolescent:
            return "Adolescent"
        case .presentNow:
            return "Present Now"
        case .dueForLesson:
            return "Due for a Lesson"
        case .withdrawn:
            return "Former Students"
        }
    }

    /// Short label used by the scope chips above the roster list.
    var chipTitle: String {
        switch self {
        case .presentNow:
            return "Here"
        case .dueForLesson:
            return "Due"
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
        case .adolescent: return "adolescent"
        case .presentNow: return "presentNow"
        case .dueForLesson: return "dueForLesson"
        case .withdrawn: return "withdrawn"
        }
    }

    /// The level this filter narrows to, if it is a level filter.
    var level: CDStudent.Level? {
        switch self {
        case .lower: return .lower
        case .upper: return .upper
        case .adolescent: return .adolescent
        default: return nil
        }
    }

    /// The filter for one level.
    static func level(_ level: CDStudent.Level) -> StudentsFilter {
        switch level {
        case .lower: return .lower
        case .upper: return .upper
        case .adolescent: return .adolescent
        }
    }
}
