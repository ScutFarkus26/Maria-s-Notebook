import SwiftUI

/// A single chat message bubble with role-appropriate styling.
/// User messages use a vibrant gradient; assistant messages render Markdown with a colorful accent.
struct ChatMessageBubble: View {
    let message: ChatMessage
    let isStreaming: Bool

    @State private var appeared = false

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
                            .font(AppTheme.ScaledFont.callout)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                    } else {
                        // Render Markdown for assistant messages
                        Text(LocalizedStringKey(message.content))
                            .font(AppTheme.ScaledFont.callout)
                            .foregroundStyle(.primary)
                    }
                }
                .textSelection(.enabled)
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.vertical, AppTheme.Spacing.compact)
                .background(bubbleBackground)
                .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.extraLarge))
                .overlay(
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.extraLarge)
                        .stroke(bubbleBorderGradient, lineWidth: isUser ? 0 : 1.5)
                )
                .shadow(isUser ? AppTheme.ShadowStyle.medium : assistantShadow)

                if !isStreaming {
                    messageFooter
                }
            }
            .scaleEffect(appeared ? 1.0 : 0.85)
            .opacity(appeared ? 1.0 : 0)

            if !isUser { Spacer(minLength: 60) }
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.9).combined(with: .opacity),
            removal: .identity
        ))
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                appeared = true
            }
        }
    }

    // MARK: - Bubble Background

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            LinearGradient(
                colors: [Color.blue, Color.purple, Color.pink.opacity(0.85)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [
                    Color.purple.opacity(0.06),
                    Color.blue.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    /// Subtle gradient border for assistant bubbles
    private var bubbleBorderGradient: some ShapeStyle {
        LinearGradient(
            colors: isUser
                ? [Color.clear]
                : [Color.purple.opacity(0.15), Color.blue.opacity(0.1)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Soft colored shadow for assistant bubbles
    private var assistantShadow: AppTheme.ShadowStyle {
        AppTheme.ShadowStyle(color: .purple.opacity(0.06), radius: 8, x: 0, y: 3)
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
}
