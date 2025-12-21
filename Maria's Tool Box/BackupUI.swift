import SwiftUI

struct BackupProgressView: View {
    let title: String
    let progress: Double
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ProgressView(value: progress) {
                Text(message)
            }
        }
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

#Preview {
    BackupProgressView(title: "Exporting…", progress: 0.42, message: "Encoding payload…")
        .padding()
}
