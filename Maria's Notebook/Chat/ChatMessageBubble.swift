import SwiftUI

/// A single chat message bubble with role-appropriate styling.
/// Assistant messages render Markdown; user messages display plain text.
struct ChatMessageBubble: View {
    let message: ChatMessage
    let isStreaming: Bool

    init(message: ChatMessage, isStreaming: Bool = false) {
        self.message = message
        self.isStreaming = isStreaming
    }

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack {
            if isUser { Spacer(minLength: 60) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: AppTheme.Spacing.xxsmall) {
                Group {
                    if isUser {
                        Text(message.content)
                            .font(AppTheme.ScaledFont.body)
                            .foregroundStyle(.white)
                    } else {
                        // Render Markdown for assistant messages
                        Text(LocalizedStringKey(message.content))
                            .font(AppTheme.ScaledFont.body)
                            .foregroundStyle(.primary)
                    }
                }
                .textSelection(.enabled)
                .padding(.horizontal, AppTheme.Spacing.compact)
                .padding(.vertical, AppTheme.Spacing.small)
                .background(
                    isUser
                        ? AnyShapeStyle(Color.accentColor)
                        : AnyShapeStyle(Color.secondary.opacity(UIConstants.OpacityConstants.faint))
                )
                .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large))

                if !isStreaming {
                    Text(message.timestamp, style: .time)
                        .font(AppTheme.ScaledFont.captionSmall)
                        .foregroundStyle(.secondary)
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
    }
}
