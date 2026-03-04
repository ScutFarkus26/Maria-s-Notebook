import SwiftUI

/// A single chat message bubble with role-appropriate styling.
/// User messages use a gradient; assistant messages render Markdown with a model badge.
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
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large))
                .shadow(isUser ? AppTheme.ShadowStyle.subtle : clearShadow)

                if !isStreaming {
                    messageFooter
                }
            }

            if !isUser { Spacer(minLength: 60) }
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity),
            removal: .identity
        ))
    }

    // MARK: - Bubble Background

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            LinearGradient(
                colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            Color.secondary.opacity(UIConstants.OpacityConstants.faint)
        }
    }

    // MARK: - Footer (timestamp + model badge)

    @ViewBuilder
    private var messageFooter: some View {
        HStack(spacing: AppTheme.Spacing.xsmall) {
            Text(message.timestamp, style: .time)
                .font(AppTheme.ScaledFont.captionSmall)
                .foregroundStyle(.secondary)

            // Model badge for assistant messages
            if !isUser, let modelID = message.modelID,
               let model = AIModelOption(rawValue: modelID) {
                ModelBadgeView(model: model, style: .compact)
            }
        }
    }

    /// A clear shadow style for assistant bubbles (no visual shadow).
    private var clearShadow: AppTheme.ShadowStyle {
        AppTheme.ShadowStyle(color: .clear, radius: 0, x: 0, y: 0)
    }
}
