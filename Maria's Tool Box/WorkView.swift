import SwiftUI

struct WorkView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "briefcase")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Work")
                .font(.title).bold()
            Text("This is a placeholder for the Work area.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.platformBackground)
    }
}

#Preview {
    WorkView()
}
