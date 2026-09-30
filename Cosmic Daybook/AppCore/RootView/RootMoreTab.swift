// RootMoreTab.swift
// The iPhone and iPad mini "More" tab: the destinations the tab bar has no
// room for, in one navigation stack the app owns.

#if os(iOS)
import SwiftUI

/// Every destination beyond the bar's four, grouped as the sidebar groups
/// them. A page opens by pushing into this tab's stack, and the pages that
/// hold a stack of their own leave it out here (`PageNavigationStack`,
/// `\.navigationPush`), so a pushed detail has one bar and one back button.
///
/// This replaces the list `TabView` built itself: that was UIKit's More
/// navigation controller, whose bar SwiftUI can't hide, so every page with
/// its own stack showed a second bar and a second back button under it.
struct RootMoreTab: View {
    @Binding var selectedNavItem: RootView.NavigationItem
    /// The destination at the bottom of `path`; nil while the list shows.
    @Binding var openItem: RootView.NavigationItem?
    @Binding var path: NavigationPath
    /// The size class the tab view's bottom-bar override hid, handed back to
    /// the pages (the iPad mini's are regular).
    let pageSizeClass: UserInterfaceSizeClass?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(RootView.NavigationGroup.secondaryGroups) { group in
                    Section(group.title) {
                        ForEach(group.secondaryItems) { item in
                            NavigationLink(value: item) {
                                Label(item.displayName, systemImage: item.icon)
                            }
                        }
                    }
                }
            }
            .navigationTitle(RootView.NavigationItem.more.displayName)
            .navigationDestination(for: RootView.NavigationItem.self) { item in
                RootDetailContent(selectedNavItem: item)
                    .environment(\.horizontalSizeClass, pageSizeClass)
                    .onAppear {
                        // `openItem` first, so `follow(_:)` sees the page already open.
                        openItem = item
                        if selectedNavItem != item { selectedNavItem = item }
                    }
            }
        }
        .environment(\.navigationPush, NavigationPushAction { path.append($0) })
        .onChange(of: selectedNavItem, initial: true) { _, item in
            follow(item)
        }
        .onChange(of: path.isEmpty) { _, isEmpty in
            guard isEmpty else { return }
            openItem = nil
            if !RootView.NavigationGroup.primaryTabs.contains(selectedNavItem) {
                selectedNavItem = .more
            }
        }
    }

    /// Opens a More destination chosen from outside the list (a router jump,
    /// the restored selection) as the stack's only page.
    private func follow(_ item: RootView.NavigationItem) {
        guard item != .more,
              !RootView.NavigationGroup.primaryTabs.contains(item),
              item != openItem else { return }
        var fresh = NavigationPath()
        fresh.append(item)
        path = fresh
        openItem = item
    }
}

#endif
