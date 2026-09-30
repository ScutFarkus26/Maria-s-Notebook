import SwiftUI

extension EnvironmentValues {
    /// The `SettingsCopy.Group.anchorID` of the card a search just jumped to.
    /// `SettingsGroup` draws a brief accent outline while it matches its own
    /// anchor. Set by `SettingsPaneScrollView`.
    @Entry var settingsHighlightedAnchor: String?
}
