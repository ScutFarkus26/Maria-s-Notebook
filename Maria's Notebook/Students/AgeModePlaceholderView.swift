import SwiftUI

struct AgeModePlaceholderView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Age Mode", systemImage: "person.crop.circle.badge.clock")
        } description: {
            Text("View students organized by age. This mode groups students by their current age and quarter-year milestones, helping you plan age-appropriate lessons and track developmental stages.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    AgeModePlaceholderView()
}
