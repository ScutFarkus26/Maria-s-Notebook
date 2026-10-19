// RootView+NavigationGroup.swift
// The one table that decides where every destination sits: the macOS sidebar,
// the iPad sidebar, and the iPhone tab bar plus its More list all read it.
// `NavigationGroupTests` pins the shape.

import Foundation

extension RootView {
    /// Sidebar / More-list groups in display order. The raw value is the
    /// suffix of the group's persisted expansion key.
    nonisolated enum NavigationGroupID: String, CaseIterable {
        // `planning` keeps its raw value for the Plan group, so a sidebar
        // collapsed under the old Planning group stays collapsed.
        case today, children, planning, classroom, library, system
    }

    nonisolated struct NavigationGroup: Identifiable, Hashable {
        let id: NavigationGroupID
        let title: String
        let items: [NavigationItem]
        /// Only Classroom starts collapsed: the room's running (Restock,
        /// schedules, outings) is reached a few times a term, not daily.
        let isExpandedByDefault: Bool

        /// Six groups, 21 rows (Simplify the app, Phase 11). The retired rows
        /// are aliases (`NavigationItem.aliases`) and open inside these.
        static let all: [NavigationGroup] = [
            .init(id: .today, title: "Today",
                  items: [.today, .attendance, .todos],
                  isExpandedByDefault: true),
            .init(id: .children, title: "Children",
                  items: [.students, .meetings, .notes, .parentReports],
                  isExpandedByDefault: true),
            .init(id: .planning, title: "Plan",
                  items: [.planningAgenda, .smallSequencePlanner, .planningChecklist, .planningCalendar,
                          .thisWeeksParsha],
                  isExpandedByDefault: true),
            .init(id: .classroom, title: "Classroom",
                  items: [.supplies, .community, .planningProjects, .goingOut, .schedules],
                  isExpandedByDefault: false),
            .init(id: .library, title: "Library",
                  items: [.lessons, .teachingAlbums, .resourceLibrary],
                  isExpandedByDefault: true),
            .init(id: .system, title: "System",
                  items: [.settings],
                  isExpandedByDefault: true)
        ]

        /// iPhone tab bar order; `RootAdaptiveTabs` adds "More" after them.
        static let primaryTabs: [NavigationItem] = [.today, .students, .attendance, .planningAgenda]

        /// This group's rows as the iPhone More list and iPad sidebar show
        /// them — the primary tabs are already in the bar, and a `Tab` may
        /// appear only once in a `TabView`.
        var secondaryItems: [NavigationItem] { items.filter { !Self.primaryTabs.contains($0) } }

        /// The groups with anything left once the primary tabs are taken out.
        static var secondaryGroups: [NavigationGroup] { all.filter { !$0.secondaryItems.isEmpty } }

        /// The group that lists the item (its canonical target for an alias).
        static func containing(_ item: NavigationItem) -> NavigationGroup? {
            all.first { $0.items.contains(item.canonical) }
        }
    }
}
