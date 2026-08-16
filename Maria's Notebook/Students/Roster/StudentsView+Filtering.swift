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
        case "adolescent": return .adolescent
        case "presentNow", "presentToday": return .presentNow
        default:
            // Includes the legacy "withdrawn" value — withdrawn students now
            // live in their own list section instead of behind a filter.
            return .all
        }
    }

    var viewStyle: StudentsViewStyle {
        #if os(macOS)
        // A Mac roster is always a table. Keep the stored preference for the
        // separate iPhone/iPad experience, but do not let it alter the desktop
        // workspace or create a second visual language there.
        return .table
        #else
        // A former Mac-only table choice should never strand a mobile user in
        // an unsupported view after switching devices.
        return StudentsViewStyle(rawValue: studentsViewStyleRaw) == .grid ? .grid : .list
        #endif
    }

    /// Whether the list/grid view-style toggle is shown (regular widths only —
    /// on iPhone the detail column is only visible when a student is pushed).
    var showsViewStyleToggle: Bool {
        #if os(iOS)
        horizontalSizeClass == .regular
        #else
        false
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

        // School-year lens: scope the roster to students active in the selected year
        // (no-op when the lens is "All years"). The withdrawn section is unaffected.
        let scoped: [CDStudent]
        if let range = dependencies.schoolYearStore.activeRange {
            scoped = base.filter { $0.isActive(in: range) }
        } else {
            scoped = base
        }

        // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
        // Use uniqueByID to prevent SwiftUI crash on "Duplicate values for key"
        return scoped.uniqueByID
    }

    /// Former students (withdrawn or transferred) for the collapsible section at the
    /// bottom of the roster. Searching the roster also matches former students.
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
