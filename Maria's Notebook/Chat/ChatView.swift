import SwiftUI
import SwiftData

/// Main chat view for the Ask AI feature.
/// Provides a conversational interface for teachers to ask questions about classroom data.
struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    @State private var viewModel = ChatViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !viewModel.hasAPIKey {
                    apiKeyPrompt
                } else {
                    chatContent
                }
            }
            .navigationTitle("Ask AI")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if viewModel.hasAPIKey && viewModel.session != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            viewModel.resetSession()
                        } label: {
                            Label("New Chat", systemImage: SFSymbol.Action.arrowCounterclockwise)
                        }
                    }
                }
            }
            .onAppear {
                viewModel.configure(
                    modelContext: modelContext,
                    mcpClient: dependencies.mcpClient
                )
            }
        }
    }

    // MARK: - Chat Content

    @ViewBuilder
    private var chatContent: some View {
        if viewModel.messages.isEmpty && !viewModel.isStreaming {
            emptyState
        } else {
            messageList
        }

        if let error = viewModel.errorMessage {
            errorBanner(error)
        }

        ChatInputBar(
            text: $viewModel.inputText,
            isLoading: viewModel.isLoading,
            canSend: viewModel.canSend,
            onSend: { viewModel.sendMessage() }
        )
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: AppTheme.Spacing.compact) {
                    ForEach(viewModel.messages) { message in
                        ChatMessageBubble(message: message)
                            .id(message.id)
                    }

                    // Show streaming content as a live-updating bubble
                    if let streaming = viewModel.streamingContent {
                        ChatMessageBubble(
                            message: ChatMessage(
                                role: .assistant,
                                content: streaming.isEmpty ? "..." : streaming
                            ),
                            isStreaming: true
                        )
                        .id("streaming")
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.vertical, AppTheme.Spacing.small)
            }
            .onChange(of: viewModel.messages.count) {
                if let last = viewModel.messages.last {
                    adaptiveWithAnimation(.easeOut(duration: UIConstants.AnimationDuration.quick)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .onChange(of: viewModel.streamingContent) {
                if viewModel.isStreaming {
                    adaptiveWithAnimation(.easeOut(duration: UIConstants.AnimationDuration.quick)) {
                        proxy.scrollTo("streaming", anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.large) {
                Spacer(minLength: AppTheme.Spacing.xxlarge)

                Image(systemName: "bubble.left.and.text.bubble.right")
                    .font(.system(size: 48))
                    .foregroundStyle(.tertiary)

                Text("Ask about your classroom")
                    .font(AppTheme.ScaledFont.header)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                    Text("Try asking...")
                        .font(AppTheme.ScaledFont.callout)
                        .foregroundStyle(.secondary)

                    ForEach(viewModel.suggestedQuestions, id: \.self) { question in
                        Button {
                            viewModel.inputText = question
                            viewModel.sendMessage()
                        } label: {
                            HStack {
                                Text(question)
                                    .font(AppTheme.ScaledFont.body)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, AppTheme.Spacing.compact)
                            .padding(.vertical, AppTheme.Spacing.small)
                            .background(Color.secondary.opacity(UIConstants.OpacityConstants.veryFaint))
                            .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.large)
            }
        }
    }

    // MARK: - API Key Prompt

    private var apiKeyPrompt: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            Spacer()
            Image(systemName: "key")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text("API Key Required")
                .font(AppTheme.ScaledFont.header)
            Text("Add your Anthropic API key in Settings to use Ask AI.")
                .font(AppTheme.ScaledFont.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(AppTheme.Spacing.large)
    }

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: AppTheme.Spacing.small) {
            Image(systemName: SFSymbol.Status.exclamationmarkTriangleFill)
                .foregroundStyle(AppColors.warning)
            Text(message)
                .font(AppTheme.ScaledFont.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: SFSymbol.Action.xmark)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppTheme.Spacing.medium)
        .padding(.vertical, AppTheme.Spacing.small)
        .background(Color.orange.opacity(UIConstants.OpacityConstants.veryFaint))
    }
}

#Preview {
    ChatView()
        .previewEnvironment()
}
