import SwiftUI

/// A consistent header component used across all main views in the app.
/// Provides a large title with optional trailing content (pickers, buttons, etc.)
struct ViewHeader<TrailingContent: View>: View {
    let title: String
    @ViewBuilder let trailingContent: () -> TrailingContent

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    init(title: String, @ViewBuilder trailingContent: @escaping () -> TrailingContent = { EmptyView() }) {
        self.title = title
        self.trailingContent = trailingContent
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.system(.largeTitle, design: .rounded).weight(.heavy))

            Spacer()

            trailingContent()
        }
        .padding()
        .backgroundPlatform()
        // Hide the parent navigation bar since ViewHeader provides its own title.
        // On iPhone compact, keep the nav bar visible for back navigation.
        #if os(iOS)
        .toolbar(horizontalSizeClass == .compact ? .automatic : .hidden, for: .navigationBar)
        #else
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

#Preview("Simple Header") {
    VStack(spacing: 0) {
        ViewHeader(title: "Today")
        Divider()
        Spacer()
    }
}

#Preview("Header with Controls") {
    VStack(spacing: 0) {
        ViewHeader(title: "Checklist") {
            Picker("Subject", selection: .constant("Biology")) {
                Text("Biology").tag("Biology")
                Text("Math").tag("Math")
            }
            .pickerStyle(.menu)
            .frame(width: 150)
        }
        Divider()
        Spacer()
    }
}
