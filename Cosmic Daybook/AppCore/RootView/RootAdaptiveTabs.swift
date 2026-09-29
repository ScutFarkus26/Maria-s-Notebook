// RootAdaptiveTabs.swift
// iOS-only adaptive tabs (iPhone and iPad mini bottom tab bar / iPad sidebar) - extracted from RootDetailContent.

#if os(iOS)
import SwiftUI

/// Adaptive tabs that show a tab bar on iPhone and a sidebar on iPad.
/// Uses `.sidebarAdaptable` so iPad users can toggle between tab bar and sidebar.
/// The iPad mini gets the iPhone's floating glass bar at the bottom instead: the
/// tab view alone sees a compact size class, and each tab's content gets the
/// real one back so its layout stays the iPad's.
///
/// The bar's four tabs and the grouped sections behind "More" both come from
/// `RootView.NavigationGroup`, the same table the macOS sidebar reads.
struct RootAdaptiveTabs: View {
    @Binding var selectedNavItem: RootView.NavigationItem
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        TabView(selection: $selectedNavItem) {
            primaryTabs
            secondaryTabs
        }
        .tabViewStyle(.sidebarAdaptable)
        .environment(\.horizontalSizeClass, Self.usesBottomTabBar ? .compact : horizontalSizeClass)
    }

    /// True on the iPad mini, the only iPad whose screen is 744 points on its
    /// short side (the next size up is 820). Reads the screen, not the window,
    /// so resizing a window never moves the bar.
    static var usesBottomTabBar: Bool {
        guard UIDevice.current.userInterfaceIdiom == .pad,
              let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else { return false }
        let bounds = scene.screen.bounds
        return min(bounds.width, bounds.height) <= 744
    }

    /// A tab's page, with the size class the tab view's override hid.
    private func page(_ item: RootView.NavigationItem) -> some View {
        RootDetailContent(selectedNavItem: item)
            .environment(\.horizontalSizeClass, horizontalSizeClass)
    }

    /// True where the secondary tabs live behind "More" rather than in a sidebar.
    private static var usesMoreList: Bool {
        UIDevice.current.userInterfaceIdiom == .phone || usesBottomTabBar
    }

    /// Pages whose root view already holds its own `NavigationStack` (or, for
    /// Students and Albums, a split view that collapses to one); a second one
    /// around them would nest stacks.
    static let pagesWithOwnStack: Set<RootView.NavigationItem> = [
        .today, .students, .attendance, .teachingAlbums,
        .settings, .askAI, .thisWeeksParsha, .parshaCalendar, .smallSequencePlanner
    ]

    /// A page on a phone-sized layout. Neither the tab bar nor the More list
    /// gives a page a navigation stack, so its title never showed and a row
    /// inside it had nowhere to push; each page without one gets its own.
    @ViewBuilder
    private func phonePage(_ item: RootView.NavigationItem) -> some View {
        if (Self.usesMoreList || horizontalSizeClass == .compact)
            && !Self.pagesWithOwnStack.contains(item.canonical) {
            NavigationStack {
                page(item)
            }
        } else {
            page(item)
        }
    }

    /// Top-level tabs (visible in the tab bar on iPhone).
    @TabContentBuilder<RootView.NavigationItem>
    private var primaryTabs: some TabContent<RootView.NavigationItem> {
        ForEach(RootView.NavigationGroup.primaryTabs) { item in
            Tab(item.displayName, systemImage: item.icon, value: item) {
                phonePage(item)
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
                        phonePage(item)
                    }
                }
            }
        }
    }
}

#endif
