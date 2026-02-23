import SwiftUI

struct LastLessonModePlaceholderView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Last Lesson Mode", systemImage: "clock.badge.exclamationmark")
        } description: {
            Text("This is a placeholder for Last Lesson Mode. Build out your last lesson mode UI here.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    LastLessonModePlaceholderView()
}


