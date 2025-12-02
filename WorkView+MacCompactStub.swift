// Provides a macOS stub for the compactWorkLayout symbol referenced in WorkView
import SwiftUI

extension WorkView {
#if os(macOS)
    @ViewBuilder
    var compactWorkLayout: some View {
        // macOS does not use the compact layout; this stub satisfies symbol resolution
        EmptyView()
    }
#endif
}
