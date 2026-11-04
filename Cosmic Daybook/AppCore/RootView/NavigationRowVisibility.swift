// NavigationRowVisibility.swift
// Empty Classroom rows stay out of the lists until their first record (plan
// "Simplify the app, round two", Phase 2).
//
// Going Out, Clubs & Projects and the Resources screen's Procedures filter
// are kept for when Danny uses them, but while they hold nothing they only
// lengthen the sidebar, the iPad sidebar and the iPhone More list. Each shows
// once a record of its kind exists. The `NavigationItem` cases stay (they are
// persisted), and a row that is selected stays listed while it is, so a
// window opened onto one (a menu command, a retired row's alias) can add the
// first record. The four iPhone tabs are never hidden.

import CoreData
import SwiftUI

nonisolated enum NavigationRowVisibility {
    /// Each hideable row and the entities whose first record shows it.
    static let rowEntities: [RootView.NavigationItem: [String]] = [
        .goingOut: ["GoingOut"],
        .planningProjects: ["Project", "BookClubSession"]
    ]

    /// The entity whose first record shows the Procedures filter.
    static let procedureEntity = "Procedure"

    /// Every entity whose saves can show or hide something here.
    static var watchedEntities: Set<String> {
        Set(rowEntities.values.flatMap(\.self)).union([procedureEntity])
    }

    /// The rows with no record yet.
    static func hiddenItems(in context: NSManagedObjectContext) -> Set<RootView.NavigationItem> {
        Set(rowEntities.compactMap { item, entities in
            entities.contains { hasRecord(of: $0, in: context) } ? nil : item
        })
    }

    /// The Resources filters with no record yet.
    static func hiddenLibraryKinds(in context: NSManagedObjectContext) -> Set<LibraryKind> {
        hasRecord(of: procedureEntity, in: context) ? [] : [.procedures]
    }

    private static func hasRecord(of entity: String, in context: NSManagedObjectContext) -> Bool {
        let request = NSFetchRequest<NSManagedObject>(entityName: entity)
        request.fetchLimit = 1
        request.includesPropertyValues = false
        return ((try? context.count(for: request)) ?? 0) > 0
    }
}

/// What one window leaves out of its lists, and what it keeps whatever:
/// the rows selected or open there.
nonisolated struct NavigationRowFilter: Equatable, Sendable {
    var hidden: Set<RootView.NavigationItem> = []
    var hiddenLibraryKinds: Set<LibraryKind> = []
    var kept: Set<RootView.NavigationItem> = []

    func shows(_ item: RootView.NavigationItem) -> Bool {
        !hidden.contains(item) || kept.contains(item)
    }

    func shows(_ kind: LibraryKind, selected: LibraryKind) -> Bool {
        !hiddenLibraryKinds.contains(kind) || kind == selected
    }
}

extension AppRouter {
    /// Hides `hidden` rows (`NavigationRowVisibility`) in a window showing
    /// `selection`: when the selection is on a row about to go, it moves to
    /// Today first (`select`), and only then do the rows go (`hide`). A
    /// `TabView` may crash with its selection on a tab it no longer has (iOS
    /// 27 release notes, 164516837); the Mac's split view gets the same order.
    /// Only a row newly hidden (not in `previouslyHidden`) moves the selection,
    /// so a window opened onto an empty row on purpose stays there; at launch
    /// nothing was hidden before, and a saved selection on one lands on Today.
    static func hideRows(
        _ hidden: Set<RootView.NavigationItem>,
        previouslyHidden: Set<RootView.NavigationItem>,
        selection: RootView.NavigationItem,
        select: (RootView.NavigationItem) -> Void,
        hide: (Set<RootView.NavigationItem>) -> Void
    ) {
        let leaving = hidden.subtracting(previouslyHidden)
        if leaving.contains(selection.canonical), !RootView.NavigationGroup.primaryTabs.contains(selection) {
            select(.today)
        }
        hide(hidden)
    }
}

extension EnvironmentValues {
    /// The window's row filter, set by `RootView`.
    @Entry var navigationRowFilter = NavigationRowFilter()
}
