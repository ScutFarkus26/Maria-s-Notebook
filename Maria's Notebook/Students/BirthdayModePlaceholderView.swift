import SwiftUI

struct BirthdayModePlaceholderView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Birthday Mode", systemImage: "gift")
        } description: {
            Text("This is a placeholder for Birthday Mode. Build out your birthday mode UI here.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    BirthdayModePlaceholderView()
}

