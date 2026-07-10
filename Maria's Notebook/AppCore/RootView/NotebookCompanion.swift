// NotebookCompanion.swift
// A useful, glanceable face for Ask AI and quick capture.

import SwiftUI
import CoreData
import OSLog

enum NotebookCompanionState: Equatable {
    case ready
    case attention
    case accomplished
    case working
}

/// A deliberately small, privacy-safe summary for the floating companion.
/// It contains counts only; student names never appear outside the opened assistant.
struct NotebookCompanionSnapshot: Equatable {
    var overdueTodoCount: Int = 0
    var dueTodayTodoCount: Int = 0
    var overduePresentationCount: Int = 0
    var scheduledPresentationCount: Int = 0
    var recordedActivityCount: Int = 0

    static let empty = NotebookCompanionSnapshot()

    var attentionCount: Int {
        overdueTodoCount + overduePresentationCount
    }

    func state(isWorking: Bool) -> NotebookCompanionState {
        if isWorking { return .working }
        if attentionCount > 0 { return .attention }
        if recordedActivityCount > 0 { return .accomplished }
        return .ready
    }

    func headline(isWorking: Bool) -> String {
        if isWorking {
            return "I'm checking your notebook…"
        }
        if overduePresentationCount > 0 {
            let suffix = overduePresentationCount == 1 ? "" : "s"
            let verb = overduePresentationCount == 1 ? "needs" : "need"
            return "\(overduePresentationCount) missed presentation\(suffix) \(verb) a decision."
        }
        if overdueTodoCount > 0 {
            let suffix = overdueTodoCount == 1 ? "" : "s"
            let verb = overdueTodoCount == 1 ? "needs" : "need"
            return "\(overdueTodoCount) overdue todo\(suffix) \(verb) attention."
        }
        if dueTodayTodoCount > 0 || scheduledPresentationCount > 0 {
            let total = dueTodayTodoCount + scheduledPresentationCount
            return "You have \(total) planned item\(total == 1 ? "" : "s") for today."
        }
        if recordedActivityCount > 0 {
            return "You've recorded \(recordedActivityCount) update\(recordedActivityCount == 1 ? "" : "s") today."
        }
        return "I'm ready when you are."
    }

    var detail: String {
        if attentionCount > 0 {
            return "I can help you decide what to handle first."
        }
        if dueTodayTodoCount > 0 || scheduledPresentationCount > 0 {
            return "Ask for a short plan, or capture what just happened."
        }
        return "Ask about the classroom or record an observation."
    }

    var briefingPrompt: String {
        """
        Give me a short, prioritized plan for today using only information recorded in my notebook. \
        Start with overdue or time-sensitive items, then scheduled presentations and useful follow-ups. \
        Keep the plan to at most five bullets. I currently see \(overdueTodoCount) overdue todos, \
        \(overduePresentationCount) missed presentations, \(dueTodayTodoCount) todos due today, and \
        \(scheduledPresentationCount) presentations scheduled today.
        """
    }

    static let followUpPrompt = """
        Which students need follow-up based on recent presentations, work, and observation notes? \
        Use only recorded evidence, give a brief reason for each suggestion, and keep the list manageable.
        """

    static let presentationPrompt = """
        Suggest the most useful next presentations for today. Use only recorded readiness, recent work, \
        lesson sequence, and presentation history. Explain each suggestion briefly and do not invent evidence.
        """
}

@Observable
@MainActor
final class NotebookCompanionViewModel {
    private static let logger = Logger.app(category: "NotebookCompanion")

    private(set) var snapshot: NotebookCompanionSnapshot = .empty

    @ObservationIgnored
    private weak var context: NSManagedObjectContext?

    func configure(context: NSManagedObjectContext) {
        if self.context !== context {
            self.context = context
        }
        reload()
    }

    func reload(now: Date = Date(), calendar: Calendar = .current) {
        guard let context else { return }

        let today = calendar.startOfDay(for: now)
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) else { return }

        let overdueTodos = count(
            entityName: "TodoItem",
            predicate: NSPredicate(
                format: "isCompleted == NO AND dueDate != nil AND dueDate < %@",
                today as NSDate
            ),
            context: context
        )
        let dueTodayTodos = count(
            entityName: "TodoItem",
            predicate: NSPredicate(
                format: "isCompleted == NO AND dueDate >= %@ AND dueDate < %@",
                today as NSDate,
                tomorrow as NSDate
            ),
            context: context
        )
        let overduePresentations = count(
            entityName: "LessonAssignment",
            predicate: NSPredicate(
                format: "stateRaw == %@ AND scheduledFor != nil AND scheduledFor < %@",
                LessonAssignmentState.scheduled.rawValue,
                today as NSDate
            ),
            context: context
        )
        let scheduledPresentations = count(
            entityName: "LessonAssignment",
            predicate: NSPredicate(
                format: "stateRaw == %@ AND scheduledFor >= %@ AND scheduledFor < %@",
                LessonAssignmentState.scheduled.rawValue,
                today as NSDate,
                tomorrow as NSDate
            ),
            context: context
        )

        let completedTodos = count(
            entityName: "TodoItem",
            predicate: NSPredicate(
                format: "completedAt >= %@ AND completedAt < %@",
                today as NSDate,
                tomorrow as NSDate
            ),
            context: context
        )
        let completedWork = count(
            entityName: "WorkModel",
            predicate: NSPredicate(
                format: "completedAt >= %@ AND completedAt < %@",
                today as NSDate,
                tomorrow as NSDate
            ),
            context: context
        )
        let presentedLessons = count(
            entityName: "LessonAssignment",
            predicate: NSPredicate(
                format: "presentedAt >= %@ AND presentedAt < %@",
                today as NSDate,
                tomorrow as NSDate
            ),
            context: context
        )
        let notes = count(
            entityName: "Note",
            predicate: NSPredicate(
                format: "createdAt >= %@ AND createdAt < %@",
                today as NSDate,
                tomorrow as NSDate
            ),
            context: context
        )

        snapshot = NotebookCompanionSnapshot(
            overdueTodoCount: overdueTodos,
            dueTodayTodoCount: dueTodayTodos,
            overduePresentationCount: overduePresentations,
            scheduledPresentationCount: scheduledPresentations,
            recordedActivityCount: completedTodos + completedWork + presentedLessons + notes
        )
    }

    private func count(
        entityName: String,
        predicate: NSPredicate,
        context: NSManagedObjectContext
    ) -> Int {
        let request = NSFetchRequest<NSFetchRequestResult>(entityName: entityName)
        request.predicate = predicate
        do {
            return try context.count(for: request)
        } catch {
            Self.logger.warning("Couldn't count \(entityName, privacy: .public): \(error.localizedDescription)")
            return 0
        }
    }
}

struct NotebookCompanionCharacter: View {
    let state: NotebookCompanionState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isBobbing = false

    private var accent: Color {
        switch state {
        case .ready: return .teal
        case .attention: return .orange
        case .accomplished: return .green
        case .working: return .purple
        }
    }

    private var badgeIcon: String {
        switch state {
        case .ready: return "sparkle"
        case .attention: return "exclamationmark"
        case .accomplished: return "checkmark"
        case .working: return "ellipsis"
        }
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            robotTeacher

            Image(systemName: badgeIcon)
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(state == .attention ? Color.red : accent))
                .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                .offset(x: 3, y: -3)
        }
        .frame(width: 58, height: 58)
        .offset(y: isBobbing ? -2 : 1)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: state == .working ? 0.65 : 1.8).repeatForever(autoreverses: true)) {
                isBobbing = true
            }
        }
        .onChange(of: reduceMotion) { _, shouldReduce in
            if shouldReduce {
                isBobbing = false
            }
        }
    }

    private var robotTeacher: some View {
        ZStack {
            HStack(spacing: 42) {
                robotEar
                robotEar
            }
            .offset(y: 6)

            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [accent.opacity(0.98), accent.opacity(0.72)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 48, height: 40)
                .overlay {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(.white.opacity(0.38), lineWidth: 1)
                }
                .offset(y: 5)

            VStack(spacing: 7) {
                HStack(spacing: 11) {
                    robotEye
                    robotEye
                }
                Capsule()
                    .fill(.white.opacity(0.92))
                    .frame(width: 16, height: 3)
            }
            .offset(y: 8)

            Image(systemName: "graduationcap.fill")
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(Color.indigo)
                .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                .offset(x: -3, y: -16)
        }
        .frame(width: 58, height: 58)
        .shadow(color: accent.opacity(0.34), radius: 8, x: 0, y: 4)
    }

    private var robotEar: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(accent.opacity(0.82))
            .frame(width: 7, height: 16)
    }

    private var robotEye: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(.white)
            .frame(width: 7, height: state == .working ? 4 : 8)
    }
}

struct NotebookCompanionPanel: View {
    enum PlacementAction {
        case moveToDesktop
        case returnToApp

        var title: String {
            switch self {
            case .moveToDesktop: return "Move to Desktop"
            case .returnToApp: return "Return to App"
            }
        }

        var icon: String {
            switch self {
            case .moveToDesktop: return "macwindow.on.rectangle"
            case .returnToApp: return "rectangle.inset.filled"
            }
        }
    }

    let snapshot: NotebookCompanionSnapshot
    let isWorking: Bool
    let onPlanDay: () -> Void
    let onFindFollowUps: () -> Void
    let onSuggestPresentations: () -> Void
    let onAskAnything: () -> Void
    let onQuickCapture: () -> Void
    let onReviewTodos: () -> Void
    var placementAction: PlacementAction?
    var onChangePlacement: (() -> Void)?

    private var state: NotebookCompanionState {
        snapshot.state(isWorking: isWorking)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            header
            summaryChips
            Divider()
            primaryAction
            suggestionGrid
            footerActions
            placementButton
        }
        .padding(AppTheme.Spacing.medium)
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 400)
        .accessibilityElement(children: .contain)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: AppTheme.Spacing.medium) {
            NotebookCompanionCharacter(state: state)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xxsmall) {
                Text("Notebook Companion")
                    .font(AppTheme.ScaledFont.calloutSemibold)
                    .foregroundStyle(.secondary)
                Text(snapshot.headline(isWorking: isWorking))
                    .font(AppTheme.ScaledFont.titleSmall)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(snapshot.detail)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var summaryChips: some View {
        if snapshot.attentionCount > 0 || snapshot.dueTodayTodoCount > 0 || snapshot.scheduledPresentationCount > 0 {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: AppTheme.Spacing.xsmall) {
                    if snapshot.attentionCount > 0 {
                        summaryChip(
                            "\(snapshot.attentionCount) overdue",
                            icon: "exclamationmark.circle.fill",
                            color: .red
                        )
                    }
                    if snapshot.dueTodayTodoCount > 0 {
                        summaryChip(
                            "\(snapshot.dueTodayTodoCount) due today",
                            icon: "checklist",
                            color: .orange
                        )
                    }
                    if snapshot.scheduledPresentationCount > 0 {
                        summaryChip(
                            "\(snapshot.scheduledPresentationCount) presentations",
                            icon: "book.fill",
                            color: .blue
                        )
                    }
                }
            }
        }
    }

    private var primaryAction: some View {
        Button(action: onPlanDay) {
            Label("Make my short plan", systemImage: "list.bullet.clipboard.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(isWorking)
    }

    private var suggestionGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: AppTheme.Spacing.xsmall
        ) {
            companionAction(
                "Who needs follow-up?",
                icon: "person.crop.circle.badge.questionmark",
                action: onFindFollowUps
            )
            companionAction(
                "Suggest presentations",
                icon: "book.pages",
                action: onSuggestPresentations
            )
        }
    }

    private var footerActions: some View {
        HStack(spacing: AppTheme.Spacing.xsmall) {
            Button(action: onQuickCapture) {
                Label("Capture", systemImage: "waveform.badge.mic")
            }
            .buttonStyle(.bordered)

            Button(action: onAskAnything) {
                Label("Ask anything", systemImage: "bubble.left.and.text.bubble.right")
            }
            .buttonStyle(.bordered)

            if snapshot.overdueTodoCount > 0 {
                Button(action: onReviewTodos) {
                    Label("Todos", systemImage: "checklist")
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var placementButton: some View {
        if let placementAction, let onChangePlacement {
            Divider()
            Button(action: onChangePlacement) {
                Label(placementAction.title, systemImage: placementAction.icon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .font(AppTheme.ScaledFont.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func summaryChip(_ title: String, icon: String, color: Color) -> some View {
        Label(title, systemImage: icon)
            .font(AppTheme.ScaledFont.captionSmallSemibold)
            .foregroundStyle(color)
            .padding(.horizontal, AppTheme.Spacing.xsmall)
            .padding(.vertical, AppTheme.Spacing.xxsmall)
            .background(Capsule().fill(color.opacity(0.10)))
    }

    private func companionAction(
        _ title: String,
        icon: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.xsmall) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .topLeading)
            .padding(AppTheme.Spacing.small)
            .background(
                RoundedRectangle(cornerRadius: UIConstants.CornerRadius.medium)
                    .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
            )
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
    }
}
