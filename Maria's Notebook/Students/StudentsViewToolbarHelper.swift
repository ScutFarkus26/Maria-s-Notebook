import SwiftUI

/// Helper for building toolbar content for StudentsView to reduce duplication
struct StudentsViewToolbarHelper {
    let mode: StudentMode
    let effectiveSortOrder: SortOrder
    let sortOrderRaw: Binding<String>
    let filterRaw: Binding<String>
    let modePickerContent: () -> any View
    let addStudentButton: () -> any View

    #if os(iOS)
    let horizontalSizeClass: UserInterfaceSizeClass?
    #endif

    var showAddButton: Bool {
        mode == .roster || mode == .age || mode == .birthday || mode == .lastLesson
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
                AnyView(addStudentButton())
            }
        }
    }

    /// Standard toolbar content for regular (iPad) layouts
    @ToolbarContentBuilder
    func regularToolbarContent() -> some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            AnyView(modePickerContent())
                .controlSize(.regular)
        }

        if showAddButton {
            ToolbarItem(placement: .primaryAction) {
                AnyView(addStudentButton())
            }
        }
    }
    #endif
}
