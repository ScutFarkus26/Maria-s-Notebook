import OSLog
import SwiftUI
import CoreData

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
        case "presentNow", "presentToday": return .presentNow
        default:
            // Includes the legacy "withdrawn" value — withdrawn students now
            // live in their own list section instead of behind a filter.
            return .all
        }
    }

    var viewStyle: StudentsViewStyle {
        StudentsViewStyle(rawValue: studentsViewStyleRaw) ?? .list
    }

    /// Whether the list/grid view-style toggle is shown (regular widths only —
    /// on iPhone the detail column is only visible when a student is pushed).
    var showsViewStyleToggle: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        true
        #endif
    }

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

    /// Count of enrolled (non-withdrawn) students, respecting the test-student toggle.
    var enrolledCount: Int {
        let hidden = hiddenTestStudentIDs
        return uniqueStudents.filter { student in
            guard student.isEnrolled else { return false }
            guard let id = student.id else { return true }
            return !hidden.contains(id)
        }.count
    }

    // OPTIMIZATION: Use cached version instead of recomputing on every view update
    var daysSinceLastLessonByStudent: [UUID: Int] { viewModel.cachedDaysSinceLastLesson }

    var filteredStudents: [CDStudent] {
        let base = viewModel.filteredStudents(
            viewContext: viewContext,
            filter: selectedFilter,
            sortOrder: sortOrder,
            searchString: searchText,
            presentNowIDs: presentNowIDs,
            showTestStudents: showTestStudents,
            testStudentNames: testStudentNamesRaw
        )

        // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
        // Use uniqueByID to prevent SwiftUI crash on "Duplicate values for key"
        return base.uniqueByID
    }

    /// Withdrawn students for the collapsible section at the bottom of the roster.
    /// Searching the roster also matches withdrawn students.
    var withdrawnStudents: [CDStudent] {
        viewModel.filteredStudents(
            viewContext: viewContext,
            filter: .withdrawn,
            sortOrder: .alphabetical,
            searchString: searchText,
            presentNowIDs: nil,
            showTestStudents: showTestStudents,
            testStudentNames: testStudentNamesRaw
        ).uniqueByID
    }
}
