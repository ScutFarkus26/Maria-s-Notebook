import SwiftUI

struct LogsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("Logs")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)

            Divider()

            ContentUnavailableView(
                "Logs",
                systemImage: "doc.text.magnifyingglass",
                description: Text("This is a placeholder for Logs. Build out your logs UI here.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 16)
    }
}

#Preview {
    LogsView()
}
