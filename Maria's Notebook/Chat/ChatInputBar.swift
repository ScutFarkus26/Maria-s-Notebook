import SwiftUI

/// Text input bar with send button for the chat interface.
struct ChatInputBar: View {
    @Binding var text: String
    let isLoading: Bool
    let canSend: Bool
    let onSend: () -> Void

    var body: some View {
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

            Button(action: onSend) {
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
            .tint(.accentColor)
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.small)
    }
}
