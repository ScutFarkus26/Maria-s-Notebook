import SwiftUI

struct ChangeLessonControl: View {
    @Binding var showLessonPicker: Bool

    var body: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showLessonPicker = true
                }
            } label: {
                Label("Change Lesson…", systemImage: "pencil")
                    .font(.system(size: AppTheme.FontSize.caption, design: .rounded))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
