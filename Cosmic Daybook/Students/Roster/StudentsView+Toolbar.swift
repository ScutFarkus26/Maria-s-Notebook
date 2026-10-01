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

        ToolbarItem(placement: .automatic) { sortMenu }
        #endif

        ToolbarItem(placement: .primaryAction) {
            addStudentMenu
        }
    }

    /// Sort menu with a checkmark on the active sort. Its label names that
    /// sort, so the order of the list is never a mystery.
    ///
    /// Buttons rather than an inline `Picker`: with the label naming the
    /// active sort, a String-tagged inline picker here crashed the iPhone app
    /// as the Students tab opened (iOS 27 simulator, 2026-10-01: EXC_BAD_ACCESS
    /// in `initializeWithCopy for Picker`, the tag's bytes retained as an
    /// object). The iPad never crashed; the old static "Sort" label never did.
    var sortMenu: some View {
        Menu {
            ForEach(Self.sortOptions, id: \.raw) { option in
                Button {
                    adaptiveWithAnimation { studentsSortOrderRaw = option.raw }
                } label: {
                    if studentsSortOrderRaw == option.raw
                        || (option.raw == "alphabetical" && sortOrder == .alphabetical) {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.up.arrow.down")
                Text(sortTitle)
            }
        }
        .help("Sort students")
        .accessibilityLabel("Sort: \(sortTitle)")
    }

    private static let sortOptions: [(raw: String, title: String)] = [
        ("alphabetical", "A–Z"),
        ("manual", "Manual"),
        ("age", "Age"),
        ("birthday", "Next Birthday")
    ]

    private var sortTitle: String {
        switch sortOrder {
        case .alphabetical: return "A–Z"
        case .manual: return "Manual"
        case .age: return "Age"
        case .birthday: return "Birthday"
        }
    }

    var addStudentMenu: some View {
        AddStudentMenu(
            onAddStudent: { showingAddStudent = true },
            onImportCSV: { showingStudentCSVImporter = true },
            onRollover: { showingRollover = true }
        )
    }
}
