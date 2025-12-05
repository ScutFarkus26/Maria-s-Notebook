import SwiftUI

extension View {
    @ViewBuilder
    func largeSheetSizing() -> some View {
        #if os(macOS)
        self
            .frame(minWidth: 720, minHeight: 640)
            .presentationSizing(.fitted)
        #else
        self
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        #endif
    }
}
