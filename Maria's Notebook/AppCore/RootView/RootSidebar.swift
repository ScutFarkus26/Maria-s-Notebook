// RootSidebar.swift
// Sidebar navigation for RootView - extracted for maintainability
//
// Both bodies read `RootView.NavigationGroup.all`; the iPhone / iPad tabs in
// RootAdaptiveTabs read the same table.

import SwiftUI
import CoreData

/// Sidebar with grouped sections (Source List style) for selecting navigation items.
struct RootSidebar: View {
    @Binding var selection: RootView.NavigationItem
    @Environment(\.appRouter) private var appRouter

    var body: some View {
        #if os(macOS)
        macOSSidebar
        #else
        visionOSSidebar
        #endif
    }
}

// MARK: - Platform Sidebars

extension RootSidebar {
    #if os(macOS)
    var macOSSidebar: some View {
        List(selection: $selection) {
            ForEach(RootView.NavigationGroup.all) { group in
                SidebarGroupSection(group: group) {
                    ForEach(group.items) { item in
                        sidebarRow(item)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        // A selection that arrives from outside the sidebar — ⌘7 Stories, a
        // restored Community, an album deep link — must not vanish into a
        // collapsed group.
        .onChange(of: selection, initial: true) { _, item in
            Self.expandGroup(containing: item)
        }
    }

    /// Marks the group holding `item` expanded when it is stored collapsed.
    /// Written straight to `UserDefaults` so every `SidebarGroupSection`'s
    /// `@AppStorage` sees it.
    private static func expandGroup(containing item: RootView.NavigationItem) {
        guard let group = RootView.NavigationGroup.containing(item) else { return }
        let key = UserDefaultsKeys.sidebarGroupExpanded(group.id.rawValue)
        let defaults = UserDefaults.standard
        let isExpanded = defaults.object(forKey: key) as? Bool ?? group.isExpandedByDefault
        if !isExpanded {
            defaults.set(true, forKey: key)
        }
    }

    @ViewBuilder
    private func sidebarRow(_ item: RootView.NavigationItem) -> some View {
        let row = Label(item.displayName, systemImage: item.icon)
            .contentShape(Rectangle())
            .tag(item)

        // Only the rows that have a menu get `.contextMenu`: an empty one
        // still pops on macOS.
        switch item {
        case .students:
            row.contextMenu {
                Button {
                    appRouter.requestNewStudent()
                } label: {
                    Label("New Student", systemImage: "person.badge.plus")
                }

                Button {
                    appRouter.requestImportStudents()
                } label: {
                    Label("Import Students…", systemImage: "square.and.arrow.down")
                }
            }
        case .planningAgenda:
            row.contextMenu {
                Button {
                    appRouter.triggerNewPresentation = true
                } label: {
                    Label("New Presentation…", systemImage: "calendar.badge.plus")
                }

                Button {
                    appRouter.requestNewWork()
                } label: {
                    Label("New Work…", systemImage: SFSymbol.Action.plusCircle)
                }
            }
        case .lessons:
            row.contextMenu {
                Button {
                    appRouter.requestNewLesson()
                } label: {
                    Label("New Lesson", systemImage: SFSymbol.Action.plusCircle)
                }

                Button {
                    appRouter.requestImportLessons()
                } label: {
                    Label("Import Lessons…", systemImage: "square.and.arrow.down")
                }
            }
        default:
            row
        }
    }
    #endif

    /// The visionOS sidebar (iOS uses `RootAdaptiveTabs` instead).
    var visionOSSidebar: some View {
        List {
            ForEach(RootView.NavigationGroup.all) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        Button { selection = item } label: {
                            Label(item.displayName, systemImage: item.icon)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(item.accessibilityHint)
                    }
                }
            }
        }
    }
}

// MARK: - Group section

#if os(macOS)
/// One sidebar group whose collapsed/expanded state outlives the window.
private struct SidebarGroupSection<Rows: View>: View {
    let group: RootView.NavigationGroup
    @ViewBuilder let rows: () -> Rows
    @AppStorage private var isExpanded: Bool

    init(group: RootView.NavigationGroup, @ViewBuilder rows: @escaping () -> Rows) {
        self.group = group
        self.rows = rows
        _isExpanded = AppStorage(
            wrappedValue: group.isExpandedByDefault,
            UserDefaultsKeys.sidebarGroupExpanded(group.id.rawValue)
        )
    }

    var body: some View {
        Section(group.title, isExpanded: $isExpanded) {
            rows()
        }
    }
}
#endif
