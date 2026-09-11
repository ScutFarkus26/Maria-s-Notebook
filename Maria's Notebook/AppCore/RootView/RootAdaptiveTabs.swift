// RootAdaptiveTabs.swift
// iOS-only adaptive tabs (iPhone tab bar / iPad sidebar) - extracted from RootDetailContent.

#if os(iOS)
import SwiftUI

/// Adaptive tabs that show a tab bar on iPhone and a sidebar on iPad.
/// Uses `.sidebarAdaptable` so iPad users can toggle between tab bar and sidebar.
///
/// The bar's four tabs and the grouped sections behind "More" both come from
/// `RootView.NavigationGroup`, the same table the macOS sidebar reads.
struct RootAdaptiveTabs: View {
    @Binding var selectedNavItem: RootView.NavigationItem

    var body: some View {
        TabView(selection: $selectedNavItem) {
            primaryTabs
            secondaryTabs
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    /// Top-level tabs (visible in the tab bar on iPhone).
    @TabContentBuilder<RootView.NavigationItem>
    private var primaryTabs: some TabContent<RootView.NavigationItem> {
        ForEach(RootView.NavigationGroup.primaryTabs) { item in
            Tab(item.displayName, systemImage: item.icon, value: item) {
                RootDetailContent(selectedNavItem: item)
            }
        }
    }

    /// Sections shown in the sidebar on iPad and under More on iPhone. The
    /// primary tabs are left out of their groups: a `Tab` may appear once.
    @TabContentBuilder<RootView.NavigationItem>
    private var secondaryTabs: some TabContent<RootView.NavigationItem> {
        ForEach(RootView.NavigationGroup.secondaryGroups) { group in
            TabSection(group.title) {
                ForEach(group.secondaryItems) { item in
                    Tab(item.displayName, systemImage: item.icon, value: item) {
                        RootDetailContent(selectedNavItem: item)
                    }
                }
            }
        }
    }
}
#endif
