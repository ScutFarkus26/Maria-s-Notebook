import SwiftUI

/// Text input bar with animated send button for the chat interface.
struct ChatInputBar: View {
    @Binding var text: String
    let isLoading: Bool
    let canSend: Bool
    let onSend: () -> Void

    @State private var sendButtonScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 0) {
            // Subtle top divider
            Rectangle()
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.subtle))
                .frame(height: UIConstants.StrokeWidth.thin)

            HStack(alignment: .bottom, spacing: AppTheme.Spacing.small) {
                TextField("Ask about your classroom...", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.horizontal, AppTheme.Spacing.compact)
                    .padding(.vertical, AppTheme.Spacing.small)
                    .background(Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint))
                    .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large))
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
                                .font(.title2)
                        }
                    }
                    .frame(width: 32, height: 32)
                }
                .disabled(!canSend)
                .scaleEffect(sendButtonScale)
                .foregroundStyle(
                    canSend && !isLoading
                        ? AnyShapeStyle(LinearGradient(
                            colors: [Color.accentColor, Color.indigo],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        : AnyShapeStyle(Color.gray.opacity(0.4))
                )
            }
            .padding(.horizontal, AppTheme.Spacing.medium)
            .padding(.vertical, AppTheme.Spacing.small)
        }
    }

    // MARK: - Send Action with Bounce

    private func triggerSend() {
        // Bounce animation
        adaptiveWithAnimation(UIConstants.SpringAnimation.bouncy) {
            sendButtonScale = 0.8
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            adaptiveWithAnimation(UIConstants.SpringAnimation.bouncy) {
                sendButtonScale = 1.0
            }
        }
        onSend()
    }

}
