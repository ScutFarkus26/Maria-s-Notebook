// WorkPrintSheet.swift
// What the printed Open Work sheet lists and how it groups it, apart from the
// Mac-only renderer (WorkPDFRenderer) so the rules can be tested.

import Foundation

enum WorkPrintSheet {

    /// One line of the sheet.
    struct Item: Identifiable {
        let id: UUID
        let lessonTitle: String
        let studentName: String
        let statusLabel: String
        /// School days since the work was last touched: the card's "Nd",
        /// printed beside each line.
        let ageDays: Int
        /// Calendar days since the work was made: what the grid's Age sort
        /// and its sections go by (`OpenWorkGrid.WorkGridItem.ageDays`).
        let createdDaysAgo: Int
        let dueAt: Date?
        let needsAttention: Bool
    }

    struct Groups {
        let sorted: [Item]
        let groups: [String: [Item]]
        let groupOrder: [String]
    }

    static func group(_ items: [Item], by sortMode: WorkAgendaSortMode) -> Groups {
        let sorted = items.sorted { lhs, rhs in
            switch sortMode {
            case .lesson: return lhs.lessonTitle.localizedCaseInsensitiveCompare(rhs.lessonTitle) == .orderedAscending
            case .student: return lhs.studentName.localizedCaseInsensitiveCompare(rhs.studentName) == .orderedAscending
            case .age: return lhs.createdDaysAgo > rhs.createdDaysAgo
            case .needsAttention:
                if lhs.needsAttention != rhs.needsAttention { return lhs.needsAttention }
                return lhs.createdDaysAgo > rhs.createdDaysAgo
            }
        }

        var groupOrder: [String] = []
        var groups: [String: [Item]] = [:]

        for item in sorted {
            let key = sectionTitle(for: item, sortMode: sortMode)
            if groups[key] == nil {
                groupOrder.append(key)
                groups[key] = []
            }
            groups[key]?.append(item)
        }

        return Groups(sorted: sorted, groups: groups, groupOrder: groupOrder)
    }

    private static func sectionTitle(for item: Item, sortMode: WorkAgendaSortMode) -> String {
        switch sortMode {
        case .lesson: return item.lessonTitle
        case .student: return item.studentName
        case .age:
            // The grid's sections, by the grid's number. The sheet used to
            // sort and bucket by school days since last touched, so it grouped
            // differently from the screen (bug hunt 2026-11-03 #44).
            return OpenWorkGrid.ageSectionTitle(forDays: item.createdDaysAgo)
        case .needsAttention:
            return item.needsAttention ? "Needs Attention" : "Other"
        }
    }
}
