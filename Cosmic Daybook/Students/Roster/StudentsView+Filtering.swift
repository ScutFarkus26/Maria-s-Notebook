import SwiftUI
import CoreData

// MARK: - The roster, derived once per render

/// Everything the Students screen draws from, built once per body pass from
/// the live roster and the view model's signals.
struct RosterSnapshot {
    /// Enrolled, visible children in the selected school year, in the active sort.
    let enrolled: [CDStudent]
    /// `enrolled` narrowed by the active scope and the search.
    let shown: [CDStudent]
    /// Former students (withdrawn or transferred) matching the search.
    let former: [CDStudent]
    /// The scope chips, each with its count.
    let scopes: [RosterScope]
}

extension StudentsView {

    var sortOrder: SortOrder {
        switch studentsSortOrderRaw {
        case "manual": return .manual
        case "age": return .age
        case "birthday": return .birthday
        default: return .alphabetical
        }
    }

    var selectedFilter: StudentsFilter {
        switch studentsFilterRaw {
        case "upper": return .upper
        case "lower": return .lower
        case "adolescent": return .adolescent
        case "presentNow", "presentToday": return .presentNow
        case "dueForLesson": return .dueForLesson
        default:
            // Includes the legacy "withdrawn" value — withdrawn students now
            // live in their own list section instead of behind a filter.
            return .all
        }
    }

    func makeSnapshot() -> RosterSnapshot {
        let all = uniqueStudents
        let show = testStudents.show
        let names = testStudents.namesRaw

        // School-year lens: scope the roster to students active in the selected
        // year (no-op when the lens is "All years"). Former students are unaffected.
        var enrolled = StudentsViewModel.filteredStudents(
            all, filter: .all, sortOrder: sortOrder, showTestStudents: show, testStudentNames: names
        )
        if let range = dependencies.schoolYearStore.activeRange {
            enrolled = enrolled.filter { $0.isActive(in: range) }
        }

        let presentIDs = viewModel.presentNowIDs
        let dueIDs = viewModel.dueIDs(among: enrolled)
        let shown = StudentsViewModel.filteredStudents(
            enrolled, filter: selectedFilter, sortOrder: sortOrder, searchString: searchText,
            presentNowIDs: presentIDs, dueIDs: dueIDs
        )
        let former = StudentsViewModel.filteredStudents(
            all, filter: .withdrawn, sortOrder: .alphabetical, searchString: searchText,
            showTestStudents: show, testStudentNames: names
        )

        var levelCounts: [CDStudent.Level: Int] = [:]
        var hereCount = 0
        for student in enrolled {
            levelCounts[student.level, default: 0] += 1
            if let id = student.id, presentIDs.contains(id) { hereCount += 1 }
        }
        var scopes = [
            RosterScope(filter: .all, count: enrolled.count),
            RosterScope(filter: .presentNow, count: hereCount),
            RosterScope(filter: .dueForLesson, count: dueIDs.count)
        ]
        // A level with no children this year has no chip, unless it is the
        // one selected (so the selection can be seen and changed).
        for level in CDStudent.Level.allCases {
            let count = levelCounts[level] ?? 0
            if count > 0 || selectedFilter.level == level {
                scopes.append(RosterScope(filter: .level(level), count: count))
            }
        }

        return RosterSnapshot(enrolled: enrolled, shown: shown, former: former, scopes: scopes)
    }
}
