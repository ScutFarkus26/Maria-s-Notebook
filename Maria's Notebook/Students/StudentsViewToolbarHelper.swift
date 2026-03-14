import SwiftUI

/// Helper for building toolbar content for StudentsView to reduce duplication
struct StudentsViewToolbarHelper<ModePicker: View, AddButton: View> {
    let mode: StudentMode
    let effectiveSortOrder: SortOrder
    let sortOrderRaw: Binding<String>
    let filterRaw: Binding<String>
    let modePickerContent: () -> ModePicker
    let addStudentButton: () -> AddButton

    #if os(iOS)
    let horizontalSizeClass: UserInterfaceSizeClass?
    #endif

    var showAddButton: Bool {
        true // All remaining modes show the add button
    }

    #if os(iOS)
    var isCompact: Bool {
        horizontalSizeClass == .compact
    }

    /// Standard toolbar content for compact (iPhone) layouts
    @ToolbarContentBuilder
    func compactToolbarContent() -> some ToolbarContent {
        if mode == .roster {
            ToolbarItem(placement: .navigationBarTrailing) {
                StudentsSortFilterMenu(
                    sortOrderRaw: sortOrderRaw,
                    filterRaw: filterRaw
                )
            }

            if effectiveSortOrder == .manual {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
            }
        }

        if showAddButton {
            ToolbarItem(placement: .primaryAction) {
                addStudentButton()
            }
        }
    }

    /// Standard toolbar content for regular (iPad) layouts
    @ToolbarContentBuilder
    func regularToolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            modePickerContent()
                .controlSize(.regular)
        }

        if showAddButton {
            ToolbarItem(placement: .primaryAction) {
                addStudentButton()
            }
        }
    }
    #endif
}
