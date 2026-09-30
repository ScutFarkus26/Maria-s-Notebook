// Opening a pane from inside another (the Overview's fix buttons): beside the
// sidebar, or pushed on iPhone, into whichever stack Settings sits in.

import SwiftUI

extension SettingsView {
    /// Opens a category from inside a pane (the Overview's fix buttons): selects
    /// it beside the sidebar, or pushes its pane on iPhone.
    func openCategory(_ category: SettingsCategory) {
        if isCompact {
            push(SettingsPaneRoute(category: category))
        } else {
            selectedCategoryRaw = category.rawValue
        }
    }

    /// Opens the category that holds a card, scrolled to the card and outlined.
    func openCard(_ group: SettingsCopy.Group) {
        if isCompact {
            push(SettingsPaneRoute(category: group.category, focus: group))
        } else {
            requestedFocus = group
            selectedCategoryRaw = group.category.rawValue
        }
    }

    private func push(_ route: SettingsPaneRoute) {
        if let enclosingPush {
            enclosingPush(route)
        } else {
            compactPath.append(route)
        }
    }
}
