import CoreData
import SwiftUI

/// A single chat message bubble with role-appropriate styling.
/// User messages use a vibrant gradient; assistant messages render Markdown with a colorful accent.
struct ChatMessageBubble: View {
    let message: ChatMessage
    let isStreaming: Bool

    @State private var appeared = false
    @Environment(\.appRouter) private var appRouter
    @Environment(\.managedObjectContext) private var viewContext
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

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

                if !isUser, !message.sources.isEmpty {
                    sourceChips
                }

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

    private var sourceChips: some View {
        FlowLayout(spacing: 6) {
            ForEach(message.sources) { source in
                Button {
                    openSource(source)
                } label: {
                    Label(source.title, systemImage: "doc.text.magnifyingglass")
                        .font(.caption)
                        .lineLimit(1)
                }
                .buttonStyle(.bordered)
                .help(source.excerpt)
            }
        }
    }

    private func openSource(_ source: EvidenceReference) {
        switch source.entityKind {
        case .note:
            #if os(macOS)
            openWindow(id: "NoteEditorWindow", value: source.entityID)
            #else
            appRouter.navigateTo(.logs)
            #endif
        case .student:
            appRouter.requestOpenStudentDetail(source.entityID)
        case .lesson:
            appRouter.navigateTo(.lessons)
        case .presentation:
            openPresentationSource(source.entityID)
        case .work:
            openWorkSource(source.entityID)
        case .todo:
            appRouter.navigateTo(.todos)
        }
    }

    private func openPresentationSource(_ id: UUID) {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1

        guard let assignment = viewContext.safeFetch(request).first else {
            appRouter.navigateToLessonsAndWork(.history, presentationID: id)
            return
        }
        if !assignment.isPresented {
            appRouter.navigateToLessonsAndWork(.upcoming, presentationID: id)
        } else if PresentationFollowUpService.hasOpenFollowUps(for: id, in: viewContext) {
            appRouter.navigateToLessonsAndWork(.needsAttention, presentationID: id)
        } else {
            appRouter.navigateToLessonsAndWork(.history, presentationID: id)
        }
    }

    private func openWorkSource(_ id: UUID) {
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        let scope: LessonsAndWorkScope = viewContext.safeFetch(request).first?.status == .complete
            ? .history
            : .childrenWorking
        appRouter.navigateToLessonsAndWork(scope, workID: id)
    }

    // MARK: - Bubble Background

    @ViewBuilder
    private var bubbleBackground: some View {
        if isUser {
            LinearGradient(
                colors: [Color.blue, Color.purple, Color.pink.opacity(UIConstants.OpacityConstants.nearSolid)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: [
                    Color.purple.opacity(UIConstants.OpacityConstants.veryFaint),
                    Color.blue.opacity(UIConstants.OpacityConstants.trace)
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
                : [
                    Color.purple.opacity(UIConstants.OpacityConstants.accent),
                    Color.blue.opacity(UIConstants.OpacityConstants.light)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Soft colored shadow for assistant bubbles
    private var assistantShadow: AppTheme.ShadowStyle {
        AppTheme.ShadowStyle(color: .purple.opacity(UIConstants.OpacityConstants.veryFaint), radius: 8, x: 0, y: 3)
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
