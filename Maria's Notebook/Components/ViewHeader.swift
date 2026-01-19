import SwiftUI

/// A consistent header component used across all main views in the app.
/// Provides a large title with optional trailing content (pickers, buttons, etc.)
struct ViewHeader<TrailingContent: View>: View {
    let title: String
    @ViewBuilder let trailingContent: () -> TrailingContent

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
