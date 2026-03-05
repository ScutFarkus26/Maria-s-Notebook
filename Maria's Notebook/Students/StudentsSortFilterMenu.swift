import SwiftUI

/// Provides reusable sort and filter menu content for the Students view.
///
/// This extracts the duplicated menu code from StudentsView's toolbar builders.
struct StudentsSortFilterMenu: View {
    @Binding var sortOrderRaw: String
    @Binding var filterRaw: String

    /// Check if current sort is alphabetical
    private var isAlphabetical: Bool {
        sortOrderRaw == "alphabetical"
            || (sortOrderRaw != "manual" && sortOrderRaw != "age"
                && sortOrderRaw != "birthday" && sortOrderRaw != "lastLesson")
    }

    /// Check if current sort is manual
    private var isManual: Bool {
        sortOrderRaw == "manual"
    }

    var body: some View {
        Menu {
            Section("Sort") {
                Button {
                    adaptiveWithAnimation { sortOrderRaw = "alphabetical" }
                } label: {
                    Label("A–Z", systemImage: "textformat.abc")
                    if isAlphabetical {
                        Image(systemName: "checkmark")
                    }
                }

                Button {
                    adaptiveWithAnimation { sortOrderRaw = "manual" }
                } label: {
                    Label("Manual", systemImage: "arrow.up.arrow.down")
                    if isManual {
                        Image(systemName: "checkmark")
                    }
                }
            }

            Section("Filter") {
                Button {
                    adaptiveWithAnimation { filterRaw = "all" }
                } label: {
                    Label("All", systemImage: "person.3.fill")
                    if filterRaw == "all"
                        || (filterRaw != "upper" && filterRaw != "lower"
                            && filterRaw != "presentNow" && filterRaw != "presentToday") {
                        Image(systemName: "checkmark")
                    }
                }

                Button {
                    adaptiveWithAnimation { filterRaw = "presentNow" }
                } label: {
                    Label("Present Now", systemImage: "checkmark.circle.fill")
                    if filterRaw == "presentNow" || filterRaw == "presentToday" {
                        Image(systemName: "checkmark")
                    }
                }

                Button {
                    adaptiveWithAnimation { filterRaw = "upper" }
                } label: {
                    Label("Upper", systemImage: "circle.fill")
                    if filterRaw == "upper" {
                        Image(systemName: "checkmark")
                    }
                }

                Button {
                    adaptiveWithAnimation { filterRaw = "lower" }
                } label: {
                    Label("Lower", systemImage: "circle.fill")
                    if filterRaw == "lower" {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            Label("Options", systemImage: "ellipsis.circle")
        }
    }
}
