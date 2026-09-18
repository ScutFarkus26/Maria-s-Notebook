import SwiftUI
import CoreData

struct PlanningSidebarView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .frame(width: UIConstants.sidebarWidth)
    }
}
