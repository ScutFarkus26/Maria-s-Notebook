import SwiftUI

struct BirthdayModePlaceholderView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Birthday Mode", systemImage: "gift")
        } description: {
            Text("See upcoming student birthdays at a glance. Students are sorted by their next birthday, so you never miss a celebration. Add student birthdays in their profile to get started.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    BirthdayModePlaceholderView()
}
