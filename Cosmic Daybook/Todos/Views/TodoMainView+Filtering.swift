// TodoMainView+Filtering.swift
// The Todos screen's filtering and sidebar counts.

import SwiftUI
import CoreData

extension TodoMainView {
    var filteredTodos: [CDTodoItem] {
        let scope = listScope
        var todos = allTodos.filter { scope.contains($0) }

        // Hide completed from all views (except the dedicated Completed filter)
        if hideCompleted && selectedFilter != .done {
            todos = todos.filter { !$0.isCompleted }
        }

        return todos.sorted { lhs, rhs in
            // Completed items always go to bottom
            if lhs.isCompleted != rhs.isCompleted {
                return !lhs.isCompleted && rhs.isCompleted
            }

            // Then sort by selected option
            switch sortBy {
            case .dueDate:
                if let lhsDate = lhs.effectiveDate, let rhsDate = rhs.effectiveDate {
                    return lhsDate < rhsDate
                }
                return lhs.effectiveDate != nil && rhs.effectiveDate == nil
            case .title:
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            case .created:
                return (lhs.createdAt ?? .distantPast) > (rhs.createdAt ?? .distantPast)
            }
        }
    }

    // PERF: Uses cached counts computed in a single pass over allTodos (refreshTagCaches).
    // Previously each call scanned allTodos independently.
    func countForFilter(_ filter: TodoListFilter) -> Int {
        cachedFilterCounts[filter] ?? 0
    }

    // MARK: - Sidebar counts

    // PERF: Compute tag data and filter/tag counts in a single pass over allTodos.
    // Previously each was a separate computed property scanning allTodos independently.
    func refreshTagCaches() {
        var filterCounts: [TodoListFilter: Int] = [:]
        var tideListCounts: [String: Int] = [:]

        for todo in allTodos {
            for filter in TodoListFilter.allCases where filter.matches(todo) {
                filterCounts[filter, default: 0] += 1
            }
            if let list = todo.tideListFile {
                tideListCounts[list, default: 0] += todo.isCompleted ? 0 : 1
            }
        }

        cachedFilterCounts = filterCounts
        cachedTideListCounts = tideListCounts
        if let list = selectedTideList, tideListCounts[list] == nil {
            selectedTideList = nil
            selectedFilter = .checkIns
        }
        // "Not yet in Tide" leaves the sidebar once it's empty.
        if selectedFilter == .notInTide, filterCounts[.notInTide] == nil {
            selectedFilter = .checkIns
        }
    }

    /// The todo fields the sidebar's counts read.
    private static let countedKeys: Set<String> = [
        "isCompleted", "linkedWorkItemID", "tideLink"
    ]

    /// Whether a change in the view context can move the sidebar's counts: a
    /// todo added, deleted or refreshed from iCloud, or one of the
    /// fields they read edited. They used to refresh only when the number of
    /// todos changed, so a tick, a new date or a new tag left them stale.
    static func changesTodoCounts(_ note: Notification) -> Bool {
        let info = note.userInfo ?? [:]
        let wholeTodoKeys = [NSInsertedObjectsKey, NSDeletedObjectsKey, NSRefreshedObjectsKey, NSInvalidatedObjectsKey]
        let touchesWholeTodo = wholeTodoKeys.contains { key in
            (info[key] as? Set<NSManagedObject>)?.contains { $0 is CDTodoItem } == true
        }
        if touchesWholeTodo || info[NSInvalidatedAllObjectsKey] != nil { return true }
        let updated = info[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? []
        return updated.contains { object in
            guard let todo = object as? CDTodoItem else { return false }
            return !countedKeys.isDisjoint(with: todo.changedValuesForCurrentEvent().keys)
        }
    }

    // MARK: - Upcoming days

    // PERF: Static cached DateFormatter to avoid allocating per call.
    // DateFormatter is expensive to create; called once per todo during grouping.
    private static let dayTimelineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()

    func dayTimelineKey(_ date: Date) -> String {
        Self.upcomingDayKey(date)
    }

    /// An Upcoming day heading, "EEE, MMM d".
    static func upcomingDayKey(_ date: Date) -> String {
        dayTimelineFormatter.string(from: date)
    }

    /// The day an Upcoming heading names. Headings carry no year, and the
    /// timeline only looks ahead, so a day that reads as earlier than
    /// `today` is next year's: in December, January's days come after
    /// December's, not before them (bug hunt 2026-10-10).
    static func upcomingDayDate(_ key: String, today: Date) -> Date? {
        let startOfToday = AppCalendar.startOfDay(today)
        dayTimelineFormatter.defaultDate = startOfToday
        guard let date = dayTimelineFormatter.date(from: key) else { return nil }
        guard date < startOfToday else { return date }
        return AppCalendar.shared.date(byAdding: .year, value: 1, to: date)
    }
}
