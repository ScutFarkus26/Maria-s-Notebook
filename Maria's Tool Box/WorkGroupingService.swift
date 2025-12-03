import Foundation

struct WorkGroupingService {
    static func sectionOrder(for grouping: WorkFilters.Grouping) -> [String] {
        switch grouping {
        case .none:
            return []
        case .type:
            return [
                WorkModel.WorkType.research.rawValue,
                WorkModel.WorkType.followUp.rawValue,
                WorkModel.WorkType.practice.rawValue
            ]
        case .date:
            return ["Today", "This Week", "Earlier"]
        case .checkIns:
            return ["Overdue", "Today", "Tomorrow", "This Week", "Future", "No Check-Ins"]
        }
    }
    
    static func sectionIcon(for key: String) -> String {
        switch key {
        case WorkModel.WorkType.research.rawValue:
            return "magnifyingglass.circle.fill"
        case WorkModel.WorkType.followUp.rawValue:
            return "bolt.circle.fill"
        case WorkModel.WorkType.practice.rawValue:
            return "arrow.triangle.2.circlepath.circle.fill"
        case "Today":
            return "sun.max.fill"
        case "This Week":
            return "calendar"
        case "Tomorrow":
            return "sunrise.fill"
        case "Overdue":
            return "exclamationmark.triangle.fill"
        case "Future":
            return "calendar.badge.clock"
        case "No Check-Ins":
            return "calendar.badge.exclamationmark"
        default:
            return "clock"
        }
    }
    
    static func groupByType(_ works: [WorkModel]) -> [String: [WorkModel]] {
        Dictionary(grouping: works, by: { $0.workType.rawValue })
    }
    
    static func groupByDate(_ works: [WorkModel], linkedDate: @escaping (WorkModel) -> Date) -> [String: [WorkModel]] {
        let cal = Calendar.current
        let today = Date()
        return Dictionary(grouping: works, by: { work in
            let d = linkedDate(work)
            if cal.isDateInToday(d) { return "Today" }
            if cal.isDate(d, equalTo: today, toGranularity: .weekOfYear) { return "This Week" }
            return "Earlier"
        })
    }
    
    static func groupByCheckIns(_ works: [WorkModel]) -> [String: [WorkModel]] {
        let cal = Calendar.current
        let today = Date()
        return Dictionary(grouping: works, by: { work in
            guard let checkIn = nextIncompleteCheckIn(for: work) else {
                return "No Check-Ins"
            }
            let d = checkIn.date
            if cal.isDateInToday(d) { return "Today" }
            if cal.isDateInTomorrow(d) { return "Tomorrow" }
            if cal.isDate(d, equalTo: today, toGranularity: .weekOfYear) { return "This Week" }
            if d < today { return "Overdue" }
            return "Future"
        })
    }
    
    static func itemsForSection(
        _ key: String,
        grouping: WorkFilters.Grouping,
        works: [WorkModel],
        linkedDate: @escaping (WorkModel) -> Date
    ) -> [WorkModel] {
        switch grouping {
        case .none:
            return []
        case .type:
            return groupByType(works)[key] ?? []
        case .date:
            return groupByDate(works, linkedDate: linkedDate)[key] ?? []
        case .checkIns:
            return groupByCheckIns(works)[key] ?? []
        }
    }
    
    private static func nextIncompleteCheckIn(for work: WorkModel) -> WorkCheckIn? {
        let incomplete = work.checkIns.filter { $0.status != .completed && $0.status != .skipped }
        return incomplete.min(by: { $0.date < $1.date })
    }
}
