import SwiftUI

// MARK: - Platform toggle style

extension View {
    /// Checkboxes read correctly in a review list on the Mac; iOS has no
    /// checkbox style, so rows there keep the default switch.
    @ViewBuilder
    func albumMatchToggleStyle() -> some View {
        #if os(macOS)
        toggleStyle(.checkbox)
        #else
        self
        #endif
    }
}
