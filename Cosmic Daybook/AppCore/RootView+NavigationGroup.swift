// RootView+NavigationGroup.swift
// The one table that decides where every destination sits: the macOS sidebar,
// the iPad sidebar, and the iPhone tab bar plus its More list all read it.
// `NavigationGroupTests` pins the shape.

import Foundation

extension RootView {
    /// Sidebar / More-list groups in display order. The raw value is the
    /// suffix of the group's persisted expansion key.
    nonisolated enum NavigationGroupID: String, CaseIterable {
        case today, children, lessonsAndWork, planning, records, library, system
    }

    nonisolated struct NavigationGroup: Identifiable, Hashable {
        let id: NavigationGroupID
        let title: String
        let items: [NavigationItem]
        /// Library is the only group that starts collapsed: it holds the
        /// reference material the guide reaches for a few times a term.
        let isExpandedByDefault: Bool

        static let all: [NavigationGroup] = [
            .init(id: .today, title: "Today",
                  items: [.today, .todos, .orders],
                  isExpandedByDefault: true),
            .init(id: .children, title: "Children",
                  items: [.students, .attendance, .meetings, .parentReports, .progressDashboard],
                  isExpandedByDefault: true),
            .init(id: .lessonsAndWork, title: "Lessons & Work",
                  items: [.planningAgenda, .lessons],
                  isExpandedByDefault: true),
            .init(id: .planning, title: "Planning",
                  items: [.planningChecklist, .curriculumMap, .planningCalendar, .smallSequencePlanner],
                  isExpandedByDefault: true),
            .init(id: .records, title: "Records",
                  items: [.logs, .notes],
                  isExpandedByDefault: true),
            .init(id: .library, title: "Library",
                  items: [.teachingAlbums, .stories, .bookClub, .procedures, .resourceLibrary, .supplies,
                          .goingOut, .community, .schedules, .thisWeeksParsha, .parshaCalendar,
                          .lessonRecall, .planningProjects],
                  isExpandedByDefault: false),
            .init(id: .system, title: "System",
                  items: [.askAI, .settings],
                  isExpandedByDefault: true)
        ]

        /// iPhone tab bar order; the `TabView` adds "More" itself.
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
