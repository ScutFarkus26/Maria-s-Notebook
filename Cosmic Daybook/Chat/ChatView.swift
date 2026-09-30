// swiftlint:disable file_length
import SwiftUI
import CoreData

// Main chat view for the Ask AI feature.
// Provides a whimsical, conversational interface for teachers to ask questions about classroom data.
// swiftlint:disable:next type_body_length
struct ChatView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var viewModel = ChatViewModel()
    @State private var iconPulse = false
    @State private var iconRotation: Double = 0
    /// Whether the hero's window can be seen: the Mac's occlusion state,
    /// always true elsewhere.
    @State private var isHeroWindowVisible = true
    @State private var cardsAppeared = false

    var body: some View {
        PageNavigationStack {
            VStack(spacing: 0) {
                chatContent
            }
            .navigationTitle("Ask AI")
            .inlineNavigationTitle()
            .toolbar {
                if viewModel.session != nil {
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
                    viewContext: viewContext,
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
            .onChange(of: viewModel.streamingContent) { previous, current in
                guard let current else { return }
                if let previous, !previous.isEmpty, !current.isEmpty {
                    // The answer growing: follow it without starting an
                    // animation on every update.
                    proxy.scrollTo("streaming", anchor: .bottom)
                } else {
                    // The typing indicator, then the first text, glide in as before.
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
                        colors: [
                            Color.purple.opacity(UIConstants.OpacityConstants.veryFaint),
                            Color.blue.opacity(UIConstants.OpacityConstants.trace)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipRounded(UIConstants.CornerRadius.extraLarge)
                .overlay(
                    RoundedRectangle(cornerRadius: UIConstants.CornerRadius.extraLarge)
                        .stroke(
                            LinearGradient(
                                colors: [
                                    Color.purple.opacity(UIConstants.OpacityConstants.accent),
                                    Color.blue.opacity(UIConstants.OpacityConstants.light)
                                ],
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
        HStack(spacing: 3) {
            Image(systemName: "apple.logo")
                .font(AppTheme.ScaledFont.captionSmall)
            Text("Responding with Apple Intelligence")
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
                                colors: [
                                    Color.purple.opacity(UIConstants.OpacityConstants.moderate),
                                    Color.blue.opacity(UIConstants.OpacityConstants.light),
                                    Color.clear
                                ],
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
                    if isHeroWindowVisible { startHeroAnimation() }
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active && isHeroWindowVisible {
                        startHeroAnimation()
                    } else {
                        stopHeroAnimation()
                    }
                }
                // `scenePhase` stays active while the Mac window is minimized,
                // covered or on another Space; nobody sees the pulse then.
                .onWindowVisibilityChange { visible in
                    isHeroWindowVisible = visible
                    if !visible {
                        stopHeroAnimation()
                    } else if scenePhase == .active {
                        startHeroAnimation()
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

    /// Starts the empty-state hero animation. Bounded rather than `repeatForever`,
    /// stopped while the scene is inactive or the window can't be seen, and
    /// restarted when it can again, so an idle, backgrounded, minimized or
    /// covered window isn't driving the render loop for nothing.
    private func startHeroAnimation() {
        guard !reduceMotion else { return }
        withAnimation(.easeInOut(duration: 2.5).repeatCount(120, autoreverses: true)) {
            iconPulse = true
        }
        withAnimation(.easeInOut(duration: 6.0).repeatCount(50, autoreverses: true)) {
            iconRotation = 8
        }
    }

    /// Snaps the hero back to rest without animating, so the next activation has a
    /// state change to animate from.
    private func stopHeroAnimation() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            iconPulse = false
            iconRotation = 0
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
                            .foregroundStyle(cardColor.opacity(UIConstants.OpacityConstants.half))
                    }
                    .padding(.horizontal, AppTheme.Spacing.medium)
                    .padding(.vertical, AppTheme.Spacing.compact)
                    .background(
                        RoundedRectangle(cornerRadius: UIConstants.CornerRadius.extraLarge)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        cardColor.opacity(UIConstants.OpacityConstants.subtle),
                                        cardColor.opacity(UIConstants.OpacityConstants.whisper)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.extraLarge)
                                    .stroke(
                                        LinearGradient(
                                            colors: [
                                                cardColor.opacity(UIConstants.OpacityConstants.quarter),
                                                cardColor.opacity(UIConstants.OpacityConstants.light)
                                            ],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        ),
                                        lineWidth: UIConstants.StrokeWidth.regular
                                    )
                            )
                    )
                    .shadow(color: cardColor.opacity(UIConstants.OpacityConstants.subtle), radius: 6, x: 0, y: 3)
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

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct ChatViewPreview: View {
    var body: some View {
        ChatView()
            .previewEnvironment()
    }
}

#Preview {
    ChatViewPreview()
}
