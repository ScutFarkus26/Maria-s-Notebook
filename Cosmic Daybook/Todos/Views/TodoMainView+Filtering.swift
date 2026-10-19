// TodoMainView+Filtering.swift
// Elegant full-screen todo list view inspired by Things and Bear

import SwiftUI
import CoreData

extension TodoMainView {
    var filteredTodos: [CDTodoItem] {
        var todos: [CDTodoItem]
        if let list = selectedTideList {
            todos = allTodos.filter { $0.tideListFile == list }
        } else if let folder = selectedFolder {
            // Show all todos that have any tag belonging to this folder
            let folderTags = Set(allUsedTags.filter {
                TodoTagHelper.tagPathComponents($0).count > 1 && TodoTagHelper.rootTagName($0) == folder
            })
            todos = allTodos.filter { todo in
                todo.tagsArray.contains(where: { folderTags.contains($0) })
            }
        } else if let tag = selectedTag {
            todos = allTodos.filter { $0.tagsArray.contains(tag) }
        } else {
            let filter = selectedFilter ?? .inbox
            todos = allTodos.filter { filter.matches($0) }
        }

        // Hide completed from all views (except the dedicated Completed filter)
        if hideCompleted && selectedFilter != .completed {
            todos = todos.filter { !$0.isCompleted }
        }

        let searchFiltered = searchText.isEmpty ? todos : todos.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            $0.notes.localizedCaseInsensitiveContains(searchText)
        }

        return searchFiltered.sorted { lhs, rhs in
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
            case .priority:
                return lhs.priority.sortOrder < rhs.priority.sortOrder
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
        guard filter != .all else { return 0 }
        return cachedFilterCounts[filter] ?? 0
    }

    func countForTag(_ tag: String) -> Int {
        cachedTagCounts[tag] ?? 0
    }

    // MARK: - Sidebar counts

    // PERF: Compute tag data and filter/tag counts in a single pass over allTodos.
    // Previously each was a separate computed property scanning allTodos independently.
    func refreshTagCaches() {
        // Build allUsedTags
        var tagSet = Set<String>()
        // Build filter counts and tag counts in the same pass
        var filterCounts: [TodoListFilter: Int] = [:]
        var tagCounts: [String: Int] = [:]
        var tideListCounts: [String: Int] = [:]
        let today = Date()

        for todo in allTodos {
            // Count filters
            for filter in TodoListFilter.allCases where filter != .all {
                if filter.matches(todo, today: today) {
                    filterCounts[filter, default: 0] += 1
                }
            }
            if let list = todo.tideListFile {
                tideListCounts[list, default: 0] += todo.isCompleted ? 0 : 1
            }
            // Collect tags and count per-tag
            for tag in todo.tagsArray {
                tagSet.insert(tag)
                if !hideCompleted || !todo.isCompleted {
                    tagCounts[tag, default: 0] += 1
                }
            }
        }

        // When hiding completed in tags, omit tags that have zero visible todos
        let visibleTags = hideCompleted ? tagSet.filter { (tagCounts[$0] ?? 0) > 0 } : tagSet
        cachedAllUsedTags = visibleTags.sorted {
            TodoTagHelper.tagName($0)
                .localizedCaseInsensitiveCompare(TodoTagHelper.tagName($1)) == .orderedAscending
        }
        cachedFilterCounts = filterCounts
        cachedTagCounts = tagCounts
        cachedTideListCounts = tideListCounts
        if let list = selectedTideList, tideListCounts[list] == nil {
            selectedTideList = nil
            selectedFilter = .inbox
        }

        // If the selected tag was hidden, deselect it
        if let selected = selectedTag, !visibleTags.contains(selected) {
            selectedTag = nil
            selectedFilter = .inbox
        }
    }

    /// The todo fields the sidebar's counts and tags read.
    private static let countedKeys: Set<String> = [
        "isCompleted", "isSomeday", "scheduledDate", "dueDate", "tags", "tideLink"
    ]

    /// Whether a change in the view context can move the sidebar's counts or
    /// tags: a todo added, deleted or refreshed from iCloud, or one of the
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
