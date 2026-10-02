import SwiftUI

extension EnvironmentValues {
    /// How far the grid's content has scrolled left past its leading edge (never negative),
    /// published once per scroll view by `stickyLeftScrollTracking()` and read by every
    /// `StickyLeftItem` inside it.
    @Entry var stickyLeftOffset: CGFloat = 0
}
