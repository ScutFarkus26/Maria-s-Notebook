import SwiftUI

struct PresentationHeaderView: View {
    let lessonName: String
    let subject: String
    let group: String
    let subjectColor: Color
    var onTapTitle: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            if let onTapTitle {
                Button(action: onTapTitle) {
                    Text(lessonName)
                        .font(AppTheme.ScaledFont.titleXLarge)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open Pages file for \(lessonName)")
            } else {
                Text(lessonName)
                    .font(AppTheme.ScaledFont.titleXLarge)
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
            .font(AppTheme.ScaledFont.captionSemibold)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(color)
            .background(
                Capsule()
                    .fill(color.opacity(UIConstants.OpacityConstants.accent))
            )
    }
}
