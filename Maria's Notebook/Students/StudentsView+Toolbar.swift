import SwiftUI

// MARK: - Toolbar Content

extension StudentsView {

    // MARK: - Mode Picker Content (for ViewHeader)

    var modePickerContent: some View {
        StudentModePicker(mode: $mode)
    }

    // MARK: - Add Student Button (for ViewHeader)

    var addStudentButton: some View {
        AddStudentButton(
            onAddStudent: { showingAddStudent = true },
            onImportCSV: { showingStudentCSVImporter = true }
        )
    }

    // MARK: - iOS-Only Toolbar Content

    #if os(iOS)
    @ToolbarContentBuilder
    var iOSToolbarContent: some ToolbarContent {
        let helper = StudentsViewToolbarHelper(
            mode: mode,
            effectiveSortOrder: effectiveSortOrder,
            sortOrderRaw: $studentsSortOrderRaw,
            filterRaw: $studentsFilterRaw,
            modePickerContent: { modePickerContent },
            addStudentButton: { addStudentButton },
            horizontalSizeClass: horizontalSizeClass
        )

        if helper.isCompact {
            helper.compactToolbarContent()
        } else {
            helper.regularToolbarContent()
        }
    }
    #endif

    // MARK: - Toolbar Content

    @ToolbarContentBuilder
    var toolbarContent: some ToolbarContent {
        #if os(iOS)
        let helper = StudentsViewToolbarHelper(
            mode: mode,
            effectiveSortOrder: effectiveSortOrder,
            sortOrderRaw: $studentsSortOrderRaw,
            filterRaw: $studentsFilterRaw,
            modePickerContent: { modePickerContent },
            addStudentButton: { addStudentButton },
            horizontalSizeClass: horizontalSizeClass
        )

        if helper.isCompact {
            helper.compactToolbarContent()
        } else {
            helper.regularToolbarContent()
        }
        #else
        ToolbarItem(placement: .automatic) {
            modePickerContent
        }

        ToolbarItem(placement: .primaryAction) {
            addStudentButton
        }
        #endif
    }
}
