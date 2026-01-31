import SwiftUI

struct StudentLessonHeaderView: View {
    let lessonName: String
    let subject: String
    let group: String
    let subjectColor: Color
    var onTapTitle: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            if let onTapTitle {
                Button(action: onTapTitle) {
                    Text(lessonName)
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Pages file for \(lessonName)")
            } else {
                Text(lessonName)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            HStack(spacing: 8) {
                if !subject.trimmed().isEmpty {
                    pillTag(subject, color: subjectColor)
                }
                if !group.trimmed().isEmpty {
                    pillTag(group, color: .secondary.opacity(0.6))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func pillTag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(color)
            .background(
                Capsule()
                    .fill(color.opacity(0.15))
            )
    }
}
