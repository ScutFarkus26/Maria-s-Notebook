import OSLog
import SwiftUI
import SwiftData

// MARK: - Filtering & Sorting Computed Properties

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
        case "presentNow": return .presentNow
        case "presentToday": return .presentNow
        case "withdrawn": return .withdrawn
        default: return .all
        }
    }

    var levelFilters: [StudentsFilter] { [.upper, .lower] }

    var hiddenTestStudentIDs: Set<UUID> {
        viewModel.hiddenTestStudentIDs(
            students: uniqueStudents,
            show: showTestStudents,
            namesRaw: testStudentNamesRaw
        )
    }

    var presentNowIDs: Set<UUID> {
        viewModel.presentNowIDs(
            from: viewModel.cachedAttendanceRecords,
            calendar: calendar
        )
    }

    var presentNowCount: Int { presentNowIDs.count }

    // OPTIMIZATION: Use cached version instead of recomputing on every view update
    var daysSinceLastLessonByStudent: [UUID: Int] { viewModel.cachedDaysSinceLastLesson }

    // Computed property to get effective sort order based on mode
    var effectiveSortOrder: SortOrder {
        switch mode {
        case .age:
            return .age
        case .birthday:
            return .birthday
        case .roster:
            return sortOrder
        case .withdrawn:
            return .alphabetical
        }
    }

    var filteredStudents: [Student] {
        let currentSortOrder = effectiveSortOrder
        let base = viewModel.filteredStudents(
            modelContext: modelContext,
            filter: selectedFilter,
            sortOrder: currentSortOrder,
            searchString: searchText,
            presentNowIDs: presentNowIDs,
            showTestStudents: showTestStudents,
            testStudentNames: testStudentNamesRaw
        )

        // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
        // Use uniqueByID to prevent SwiftUI crash on "Duplicate values for key"
        return base.uniqueByID
    }

    // MARK: - Grid View Support

    var shouldUseGridView: Bool {
        mode == .age || mode == .birthday
    }

    #if DEBUG
    // Temporary helper to check for duplicate IDs (debug only)
    func checkForDuplicateIDs(in students: [Student]) {
        let uniqueIDs = Set(students.map { $0.id })
        if uniqueIDs.count != students.count {
            Logger.students.warning(
                "Found \(students.count - uniqueIDs.count, privacy: .public) duplicate student ID(s)"
            )
        }
    }
    #endif
}
