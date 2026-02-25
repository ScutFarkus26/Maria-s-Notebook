import SwiftUI

/// A single chat message bubble with role-appropriate styling.
struct ChatMessageBubble: View {
    let message: ChatMessage

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text(message.content)
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(isUser ? .white : .primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, AppTheme.Spacing.compact)
                    .padding(.vertical, AppTheme.Spacing.small)
                    .background(
                        isUser
                            ? AnyShapeStyle(Color.accentColor)
                            : AnyShapeStyle(Color.secondary.opacity(UIConstants.OpacityConstants.faint))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large))

                Text(message.timestamp, style: .time)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }
}
