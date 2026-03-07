// swiftlint:disable file_length
import SwiftUI
import SwiftData

// Main chat view for the Ask AI feature.
// Provides a whimsical, conversational interface for teachers to ask questions about classroom data.
// swiftlint:disable:next type_body_length
struct ChatView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dependencies) private var dependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var viewModel = ChatViewModel()
    @State private var iconPulse = false
    @State private var iconRotation: Double = 0
    @State private var cardsAppeared = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if viewModel.needsAPIKey {
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
                // Model indicator in toolbar
                #if os(macOS)
                ToolbarItem(placement: .navigation) {
                    ModelBadgeView(model: viewModel.currentModel, style: .toolbar)
                }
                #else
                ToolbarItem(placement: .topBarLeading) {
                    ModelBadgeView(model: viewModel.currentModel, style: .toolbar)
                }
                #endif

                if !viewModel.needsAPIKey && viewModel.session != nil {
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
                        if message.isEscalationPrompt {
                            escalationPromptCard
                                .id(message.id)
                        } else {
                            ChatMessageBubble(message: message)
                                .id(message.id)
                        }
                    }

                    // Show streaming content or typing indicator
                    if let streaming = viewModel.streamingContent {
                        if streaming.isEmpty {
                            // Animated typing indicator while waiting for first token
                            typingIndicatorBubble
                                .id("streaming")
                        } else {
                            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                                ChatMessageBubble(
                                    message: ChatMessage(
                                        role: .assistant,
                                        content: streaming
                                    ),
                                    isStreaming: true
                                )

                                streamingModelLabel
                            }
                            .id("streaming")
                        }
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.vertical, AppTheme.Spacing.small)
                .animation(
                    reduceMotion ? nil : UIConstants.SpringAnimation.standard,
                    value: viewModel.messages.count
                )
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

    // MARK: - Typing Indicator Bubble

    private var typingIndicatorBubble: some View {
        HStack {
            TypingIndicatorView()
                .padding(.horizontal, AppTheme.Spacing.medium)
                .padding(.vertical, AppTheme.Spacing.compact)
                .background(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.06), Color.blue.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: UIConstants.CornerRadius.extraLarge))
                .overlay(
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.extraLarge)
                        .stroke(
                            LinearGradient(
                                colors: [Color.purple.opacity(0.15), Color.blue.opacity(0.1)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1.5
                        )
                )
            Spacer(minLength: 60)
        }
    }

    // MARK: - Streaming Model Label

    private var streamingModelLabel: some View {
        let model = viewModel.isEscalating ? AIModelOption.claudeSonnet : viewModel.currentModel
        return HStack(spacing: 3) {
            Image(systemName: model.iconName)
                .font(AppTheme.ScaledFont.captionSmall)
            Text("Responding with \(model.displayName)")
                .font(AppTheme.ScaledFont.captionSmall)
        }
        .foregroundStyle(.tertiary)
        .padding(.leading, AppTheme.Spacing.xsmall)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: AppTheme.Spacing.large) {
                Spacer(minLength: AppTheme.Spacing.xlarge)

                // Large animated gradient icon with glow
                ZStack {
                    // Glow effect behind icon
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.purple.opacity(0.2), Color.blue.opacity(0.1), Color.clear],
                                center: .center,
                                startRadius: 20,
                                endRadius: 80
                            )
                        )
                        .frame(width: 160, height: 160)
                        .scaleEffect(iconPulse ? 1.1 : 0.9)

                    Image(systemName: SFSymbol.Tool.wand)
                        .font(.system(size: 72, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.pink, .purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .scaleEffect(iconPulse ? 1.08 : 1.0)
                        .rotationEffect(.degrees(iconRotation))
                }
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
                        iconPulse = true
                    }
                    withAnimation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true)) {
                        iconRotation = 8
                    }
                }

                // Vibrant greeting
                VStack(spacing: AppTheme.Spacing.small) {
                    Text("Hello! I know your classroom inside and out.")
                        .font(AppTheme.ScaledFont.titleLarge)
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .multilineTextAlignment(.center)

                    Text("Ask me anything about your students, lessons, or schedule.")
                        .font(AppTheme.ScaledFont.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                // Model badge
                ModelBadgeView(model: viewModel.currentModel, style: .standard)

                // Suggestion cards with staggered animation
                suggestionCards
                    .onAppear {
                        guard !reduceMotion else {
                            cardsAppeared = true
                            return
                        }
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.3)) {
                            cardsAppeared = true
                        }
                    }
            }
            .padding(.horizontal, AppTheme.Spacing.large)
        }
    }

    // MARK: - Suggestion Cards

    /// Colors used for suggestion card accents
    private static let cardColors: [Color] = [.pink, .purple, .blue, .teal]

    private var suggestionCards: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
            Text("Try asking...")
                .font(AppTheme.ScaledFont.titleSmall)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .pink],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            ForEach(Array(viewModel.suggestedQuestions.enumerated()), id: \.element) { index, question in
                let cardColor = Self.cardColors[index % Self.cardColors.count]
                Button {
                    viewModel.inputText = question
                    viewModel.sendMessage()
                } label: {
                    HStack(spacing: AppTheme.Spacing.small) {
                        Image(systemName: "sparkles")
                            .font(.callout)
                            .foregroundStyle(cardColor)
                        Text(question)
                            .font(AppTheme.ScaledFont.callout)
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Spacer()
                        Image(systemName: "arrow.up.right.circle.fill")
                            .font(.callout)
                            .foregroundStyle(cardColor.opacity(0.5))
                    }
                    .padding(.horizontal, AppTheme.Spacing.medium)
                    .padding(.vertical, AppTheme.Spacing.compact)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.extraLarge)
                            .fill(
                                LinearGradient(
                                    colors: [cardColor.opacity(0.08), cardColor.opacity(0.03)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.extraLarge)
                                    .stroke(
                                        LinearGradient(
                                            colors: [cardColor.opacity(0.25), cardColor.opacity(0.1)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: UIConstants.StrokeWidth.regular
                                    )
                            )
                    )
                    .shadow(color: cardColor.opacity(0.08), radius: 6, x: 0, y: 3)
                }
                .buttonStyle(.plain)
                .opacity(cardsAppeared ? 1 : 0)
                .offset(y: cardsAppeared ? 0 : 15)
                .animation(
                    reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.7).delay(Double(index) * 0.1),
                    value: cardsAppeared
                )
            }
        }
    }

    // MARK: - Escalation Prompt Card

    private var escalationPromptCard: some View {
        HStack {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                HStack(spacing: AppTheme.Spacing.xsmall) {
                    Image(systemName: "arrow.up.circle")
                        .font(.subheadline)
                        .foregroundStyle(.purple)
                    Text("This answer might be improved with Claude.")
                        .font(AppTheme.ScaledFont.callout)
                        .foregroundStyle(.primary)
                }

                Text("Want me to optimize and retry with a cloud model?")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: AppTheme.Spacing.compact) {
                    Button {
                        viewModel.acceptEscalation()
                    } label: {
                        Label("Try with Claude", systemImage: "bolt.circle")
                            .font(AppTheme.ScaledFont.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .controlSize(.small)

                    Button {
                        viewModel.dismissEscalation()
                    } label: {
                        Text("Dismiss")
                            .font(AppTheme.ScaledFont.caption)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(AppTheme.Spacing.compact)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                    .fill(Color.purple.opacity(UIConstants.OpacityConstants.veryFaint))
                    .overlay(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large)
                            .stroke(
                                Color.purple.opacity(UIConstants.OpacityConstants.subtle),
                                lineWidth: UIConstants.StrokeWidth.thin
                            )
                    )
            )
            Spacer(minLength: 60)
        }
        .transition(.asymmetric(
            insertion: .scale(scale: 0.95).combined(with: .opacity),
            removal: .opacity
        ))
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
            let modelName = viewModel.currentModel.displayName
            Text(
                """
                The selected model (\(modelName)) requires \
                an Anthropic API key. Add one in Settings, \
                or switch to a local model.
                """
            )
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
