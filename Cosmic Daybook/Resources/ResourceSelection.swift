// ResourceSelection.swift
// What the Resources library's select mode acts on: the bulk actions, the
// selected count and Select All.
//
// A filter (a category, a tag, a search) can hide resources the guide ticked
// earlier. They stay ticked for when the filter changes back, but nothing acts
// on them while she can't see them: Delete used to remove worksheets she could
// no longer see, and Select All compared counts, so a hidden tick could make
// it read Deselect All.

import Foundation

struct ResourceSelection {
    /// The resources on screen, in their order.
    let visibleIDs: [UUID]
    /// Every resource the guide has ticked, shown or not.
    let selectedIDs: Set<UUID>

    /// The resources a bulk action (Favorite, Categorize, Tag, Delete) changes,
    /// and the count the select bar shows: the ticked ones she can see.
    var actedOnIDs: Set<UUID> {
        selectedIDs.intersection(visibleIDs)
    }

    /// True when every resource on screen is ticked, so Select All reads Deselect All.
    var allVisibleSelected: Bool {
        !visibleIDs.isEmpty && visibleIDs.allSatisfy(selectedIDs.contains)
    }

    /// The selection after Select All (or Deselect All), which changes only
    /// what's on screen.
    func togglingAll() -> Set<UUID> {
        allVisibleSelected ? selectedIDs.subtracting(visibleIDs) : selectedIDs.union(visibleIDs)
    }
}
