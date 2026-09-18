import SwiftUI

/// Small overlay used on a card while a story is being analyzed.
struct StoryImportProgressView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
            VStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Analyzing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
