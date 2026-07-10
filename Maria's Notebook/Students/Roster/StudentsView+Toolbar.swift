import SwiftUI
import CoreData

// MARK: - Toolbar Content

extension StudentsView {

    /// Toolbar for the sidebar (roster) column. On iPhone this is the only
    /// toolbar visible until a student is pushed, so everything lives here.
    @ToolbarContentBuilder
    var sidebarToolbar: some ToolbarContent {
        #if os(iOS)
        if sortOrder == .manual {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
        }
        #endif

        ToolbarItem(placement: .automatic) {
            sortMenu
        }

        if showsViewStyleToggle {
            ToolbarItem(placement: .automatic) {
                viewStylePicker
            }
        }

        ToolbarItem(placement: .primaryAction) {
            addStudentMenu
        }
    }

    /// Sort menu with radio-style selection. The chosen sort also drives the
    /// row accessory (birthday countdown, age, or days since last lesson).
    var sortMenu: some View {
        Menu {
            Picker("Sort", selection: sortSelection) {
                Label("A–Z", systemImage: "textformat.abc")
                    .tag("alphabetical")
                Label("Manual", systemImage: "arrow.up.arrow.down")
                    .tag("manual")
                Label("Age", systemImage: "calendar")
                    .tag("age")
                Label("Next Birthday", systemImage: "gift")
                    .tag("birthday")
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort", systemImage: "arrow.up.arrow.down")
        }
        .help("Sort students")
    }

    private var sortSelection: Binding<String> {
        Binding(
            get: { studentsSortOrderRaw },
            set: { newValue in
                adaptiveWithAnimation { studentsSortOrderRaw = newValue }
            }
        )
    }

    /// List/grid toggle for the detail area browser (regular widths only).
    var viewStylePicker: some View {
        Picker("View Style", selection: viewStyleSelection) {
            Label("List", systemImage: "list.bullet")
                .tag(StudentsViewStyle.list)
            Label("Grid", systemImage: "square.grid.2x2")
                .tag(StudentsViewStyle.grid)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .help("Switch between list and card grid")
    }

    private var viewStyleSelection: Binding<StudentsViewStyle> {
        Binding(
            get: { viewStyle },
            set: { newValue in
                adaptiveWithAnimation { studentsViewStyleRaw = newValue.rawValue }
            }
        )
    }

    var addStudentMenu: some View {
        AddStudentMenu(
            onAddStudent: { showingAddStudent = true },
            onImportCSV: { showingStudentCSVImporter = true }
        )
    }
}
