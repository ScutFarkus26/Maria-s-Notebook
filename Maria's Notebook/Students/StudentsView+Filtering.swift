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
        case "lastLesson": return .lastLesson
        default: return .alphabetical
        }
    }

    var selectedFilter: StudentsFilter {
        switch studentsFilterRaw {
        case "upper": return .upper
        case "lower": return .lower
        case "presentNow": return .presentNow
        case "presentToday": return .presentNow
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
        case .lastLesson:
            return .lastLesson
        case .roster:
            return sortOrder
        case .workOverview, .observationHeatmap:
            return .alphabetical // Not used in these modes
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
        let deduplicated = base.uniqueByID

        // Apply lastLesson sorting in-memory (requires access to presentation data)
        if currentSortOrder == .lastLesson {
            let daysMap = daysSinceLastLessonByStudent
            return deduplicated.sorted { lhs, rhs in
                let lDays = daysMap[lhs.id] ?? -1
                let rDays = daysMap[rhs.id] ?? -1
                // Students with no presentations (-1) go first, then sort by most days since last presentation
                if lDays == -1 && rDays == -1 {
                    return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
                }
                if lDays == -1 { return true }
                if rDays == -1 { return false }
                if lDays == rDays {
                    return lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
                }
                return lDays > rDays // More days = needs lesson more urgently
            }
        }

        return deduplicated
    }

    // MARK: - Grid View Support

    var shouldUseGridView: Bool {
        mode == .age || mode == .birthday || mode == .lastLesson
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
