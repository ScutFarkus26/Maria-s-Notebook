import SwiftUI

struct LogsView: View {
    var body: some View {
        VStack(spacing: 0) {
            ViewHeader(title: "Logs")
            Divider()

            ContentUnavailableView(
                "Logs",
                systemImage: "doc.text.magnifyingglass",
                description: Text("This is a placeholder for Logs. Build out your logs UI here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#Preview {
    LogsView()
}
