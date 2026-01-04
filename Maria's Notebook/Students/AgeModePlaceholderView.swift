import SwiftUI

struct AgeModePlaceholderView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Age Mode", systemImage: "calendar")
        } description: {
            Text("This is a placeholder for Age Mode. Build out your age mode UI here.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AgeModePlaceholderView()
}

