import SwiftUI

/// Text input bar with animated send button for the chat interface.
struct ChatInputBar: View {
    @Binding var text: String
    let isLoading: Bool
    let canSend: Bool
    let onSend: () -> Void

    @State private var sendButtonScale: CGFloat = 1.0
    @State private var sendButtonRotation: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            // Gradient top divider
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [.purple.opacity(UIConstants.OpacityConstants.semi), .blue.opacity(UIConstants.OpacityConstants.moderate), .pink.opacity(UIConstants.OpacityConstants.semi)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(height: 1.5)

            HStack(alignment: .bottom, spacing: AppTheme.Spacing.compact) {
                TextField("Ask about your classroom...", text: $text, axis: .vertical)
                    .font(AppTheme.ScaledFont.callout)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.horizontal, AppTheme.Spacing.medium)
                    .padding(.vertical, AppTheme.Spacing.compact)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.extraLarge)
                            .fill(Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.extraLarge)
                            .stroke(
                                LinearGradient(
                                    colors: [.purple.opacity(UIConstants.OpacityConstants.accent), .blue.opacity(UIConstants.OpacityConstants.accent)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .onSubmit {
                        if canSend { onSend() }
                    }

                Button(action: triggerSend) {
                    Group {
                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: SFSymbol.Arrow.upCircleFill)
                                .font(.title)
                        }
                    }
                    .frame(width: 40, height: 40)
                }
                .disabled(!canSend)
                .scaleEffect(sendButtonScale)
                .rotationEffect(.degrees(sendButtonRotation))
                .foregroundStyle(
                    canSend && !isLoading
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Color.pink, Color.purple, Color.blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        : AnyShapeStyle(Color.gray.opacity(UIConstants.OpacityConstants.semi))
                )
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.compact)
        }
    }

    // MARK: - Send Action with Bounce + Spin

    private func triggerSend() {
        // Bounce + spin animation
        adaptiveWithAnimation(.spring(response: 0.25, dampingFraction: 0.6)) {
            sendButtonScale = 0.7
            sendButtonRotation = -30
        }
        Task {
            try? await Task.sleep(for: .milliseconds(120))
            adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.5)) {
                sendButtonScale = 1.1
                sendButtonRotation = 0
            }
            try? await Task.sleep(for: .milliseconds(230))
            adaptiveWithAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                sendButtonScale = 1.0
            }
        }
        onSend()
    }

}
