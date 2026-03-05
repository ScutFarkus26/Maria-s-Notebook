import SwiftUI

struct LastLessonModePlaceholderView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Last Lesson Mode", systemImage: "clock.badge.exclamationmark")
        } description: {
            Text(
                "Identify students who need attention based on how long it has been" +
                " since their last lesson. Students are sorted by days since their" +
                " most recent presentation, making it easy to ensure no one falls behind."
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LastLessonModePlaceholderView()
}
