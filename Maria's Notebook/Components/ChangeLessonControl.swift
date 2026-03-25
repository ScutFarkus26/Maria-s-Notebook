import SwiftUI

struct ChangeLessonControl: View {
    @Binding var showLessonPicker: Bool

    var body: some View {
        HStack {
            Button {
                _ = adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                    showLessonPicker = true
                }
            } label: {
                Label("Change Lesson…", systemImage: "pencil")
                    .font(AppTheme.ScaledFont.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            Spacer()
        }
    }
}
