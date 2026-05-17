import SwiftUI
import CoreData

struct PresentationHeaderView: View {
    let lessonName: String
    let area: String
    let sequence: String
    let areaColor: Color
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
                if !area.trimmed().isEmpty {
                    pillTag(area, color: areaColor)
                }
                if !sequence.trimmed().isEmpty {
                    pillTag(sequence, color: .secondary.opacity(0.6))
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
