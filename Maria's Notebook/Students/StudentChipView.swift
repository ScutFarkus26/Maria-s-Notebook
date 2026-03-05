import SwiftUI

struct ChipView: View {
    let label: String
    let isMissing: Bool
    let isAbsent: Bool
    let subjectColor: Color
    let hasHad: Bool
    let suppressIndicator: Bool
    let highlight: Bool
    let blockingWork: WorkModel?

    var onTap: (() -> Void)?

    var body: some View {
        // If tappable (has blocking contract), wrap in button to capture touch
        if blockingWork != nil {
            Button {
                onTap?()
            } label: {
                content
            }
            .buttonStyle(.plain)
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        HStack(spacing: 4) {
            if blockingWork != nil {
                // Minimalist "waiting" indicator
                Image(systemName: "hourglass")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(AppColors.warning)
            }
            Text(label)
                .font(AppTheme.ScaledFont.captionSmallSemibold)
        }
        // Standard text color for readability
        .foregroundStyle(isMissing || isAbsent ? .secondary : .primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(isMissing ? Color.primary.opacity(0.06) : subjectColor.opacity(isAbsent ? 0.06 : 0.15))
        )
        .overlay(
            Capsule().stroke(
                // Only use red stroke for absence, orange for "missed lesson", clear for blocking (keeps it regular)
                isAbsent ? Color.red : (highlight ? Color.orange : Color.clear),
                lineWidth: 1
            )
        )
    }
}
