// QuickNoteGlassButton.swift
// Floating notebook companion. A long press preserves the original quick-create menu.

import SwiftUI

// Isolated component to prevent RootView re-renders during drag
// swiftlint:disable:next type_body_length
struct QuickNoteGlassButton: View {
    @Binding var isShowingCommandBar: Bool
    var onNewPresentation: () -> Void
    @Binding var isShowingWorkItemSheet: Bool
    var onRecordPractice: () -> Void
    var onNewTodo: () -> Void
    var onNewNote: () -> Void
    let companionSnapshot: NotebookCompanionSnapshot
    let isAIWorking: Bool
    var onAskAI: (String?) -> Void
    var onReviewTodos: () -> Void
    var onRefreshCompanion: () -> Void

    @State private var offset: CGSize = .zero
    @State private var isPressed: Bool = false
    @State private var isPieMenuExpanded: Bool = false
    @State private var isCompanionPresented: Bool = false
    @State private var highlightedAction: PieMenuAction?
    @State private var dragTranslation: CGSize = .zero
    @State private var longPressTask: Task<Void, Never>?
    @State private var sparklePhase: Bool = false

    @AppStorage(UserDefaultsKeys.quickNoteButtonOffsetX) private var savedOffsetX: Double = 0
    @AppStorage(UserDefaultsKeys.quickNoteButtonOffsetY) private var savedOffsetY: Double = 0

    private let pieMenuRadius: CGFloat = 95
    private let longPressDuration: Duration = .milliseconds(400) // 0.4 seconds

    var body: some View {
        accessibilityContent
    }

    private var floatingContent: some View {
        // Main button with fixed size
        visualContent
            .scaleEffect(isPressed && !isPieMenuExpanded ? 0.92 : 1.0)
            .adaptiveAnimation(.easeInOut(duration: 0.1), value: isPressed)
            .overlay {
                // Pie menu segments overlay (doesn't affect button layout)
                if isPieMenuExpanded {
                    pieMenuOverlay
                }
            }
        .offset(offset)
        .padding(.trailing, AppTheme.Spacing.large)
        #if os(iOS)
        // 32 + 16 = 48pt base, plus 37pt for safe area
        .padding(.bottom, AppTheme.Spacing.xlarge + AppTheme.Spacing.medium)
        #else
        .padding(.bottom, AppTheme.Spacing.medium + AppTheme.Spacing.small) // 16 + 8 = 24pt base
        #endif
        .gesture(combinedGesture)
        .onAppear {
            self.offset = CGSize(width: savedOffsetX, height: savedOffsetY)
        }
        .onChange(of: isPieMenuExpanded) { _, expanded in
            sparklePhase = expanded
        }
        .onDisappear {
            longPressTask?.cancel()
        }
        .popover(isPresented: $isCompanionPresented, arrowEdge: .bottom) {
            companionPanel
        }
    }

    @ViewBuilder
    private var pointerContent: some View {
        // macOS: a standard right-click menu exposes every action to pointer users
        // (the long-press radial menu has no pointer/keyboard equivalent on its own).
        // On iOS the long-press already drives the pie menu, so no contextMenu there.
        #if os(macOS)
        floatingContent
            .contextMenu {
                companionContextMenu
            }
            .help("Notebook companion — right-click for actions")
        #else
        floatingContent
        #endif
    }

    private var accessibilityContent: some View {
        pointerContent
        .accessibilityLabel(companionAccessibilityLabel)
        .accessibilityHint("Opens the notebook companion")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open Notebook Companion") { openCompanion() }
        .accessibilityAction(named: "Quick Capture") { isShowingCommandBar = true }
    }

    #if os(macOS)
    @ViewBuilder
    private var companionContextMenu: some View {
        Button {
            onAskAI(nil)
        } label: {
            Label("Ask My Notebook", systemImage: "bubble.left.and.text.bubble.right")
        }
        Button {
            onAskAI(companionSnapshot.briefingPrompt)
        } label: {
            Label("Make My Short Plan", systemImage: "list.bullet.clipboard.fill")
        }
        Button {
            onAskAI(NotebookCompanionSnapshot.followUpPrompt)
        } label: {
            Label("Who Needs Follow-up?", systemImage: "person.crop.circle.badge.questionmark")
        }
        Divider()
        ForEach(PieMenuAction.allCases, id: \.self) { action in
            Button {
                executeAction(action)
            } label: {
                Label(action.label, systemImage: action.icon)
            }
        }
    }
    #endif

    private var pieMenuOverlay: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [
                            .cyan.opacity(UIConstants.OpacityConstants.muted),
                            .pink.opacity(UIConstants.OpacityConstants.muted),
                            .mint.opacity(UIConstants.OpacityConstants.muted),
                            .cyan.opacity(UIConstants.OpacityConstants.muted)
                        ],
                        center: .center
                    )
                )
                .blur(radius: 12)
                .frame(width: pieMenuRadius * 2 + 26, height: pieMenuRadius * 2 + 26)
                .scaleEffect(sparklePhase ? 1.04 : 0.96)
                .opacity(UIConstants.OpacityConstants.barelyTransparent)
                .adaptiveAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: sparklePhase)

            ForEach(0..<6, id: \.self) { index in
                Image(systemName: "sparkle")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(UIConstants.OpacityConstants.nearSolid))
                    .offset(orbitOffset(for: index, radius: pieMenuRadius + 20))
                    .rotationEffect(.degrees(sparklePhase ? 360 : 0))
                    .opacity(UIConstants.OpacityConstants.heavy)
                    .adaptiveAnimation(
                        .linear(duration: 2.6 + Double(index) * 0.2)
                            .repeatForever(autoreverses: false),
                        value: sparklePhase
                    )
            }

            ForEach(PieMenuAction.allCases, id: \.self) { action in
                PieMenuSegment(
                    action: action,
                    isExpanded: isPieMenuExpanded,
                    isHighlighted: highlightedAction == action,
                    radius: pieMenuRadius
                )
            }
        }
        .background(
            Circle()
                .fill(.ultraThinMaterial)
                .frame(
                    width: pieMenuRadius * 2 + AppTheme.Spacing.large,
                    height: pieMenuRadius * 2 + AppTheme.Spacing.large
                )
                .opacity(isPieMenuExpanded ? 1.0 : 0.0)
        )
    }

    private var visualContent: some View {
        ZStack(alignment: .bottomTrailing) {
            if isPieMenuExpanded {
                Image(systemName: "xmark")
                    .font(.system(size: 23, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 58, height: 58)
                    .background(
                        Circle().fill(
                            LinearGradient(
                                colors: [.pink, .orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    )
                    .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
            } else {
                NotebookCompanionCharacter(
                    state: companionSnapshot.state(isWorking: isAIWorking)
                )
            }

            if companionSnapshot.attentionCount > 0 && !isPieMenuExpanded {
                Text(companionSnapshot.attentionCount > 9 ? "9+" : "\(companionSnapshot.attentionCount)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(minWidth: 20, minHeight: 20)
                    .background(Circle().fill(.red))
                    .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                    .offset(x: 3, y: 3)
            }
        }
        .frame(width: 62, height: 62)
        .contentShape(Circle())
        .adaptiveAnimation(.spring(response: 0.3, dampingFraction: 0.7), value: isPieMenuExpanded)
    }

    private var companionPanel: some View {
        NotebookCompanionPanel(
            snapshot: companionSnapshot,
            isWorking: isAIWorking,
            onPlanDay: {
                performCompanionAction {
                    onAskAI(companionSnapshot.briefingPrompt)
                }
            },
            onFindFollowUps: {
                performCompanionAction {
                    onAskAI(NotebookCompanionSnapshot.followUpPrompt)
                }
            },
            onSuggestPresentations: {
                performCompanionAction {
                    onAskAI(NotebookCompanionSnapshot.presentationPrompt)
                }
            },
            onAskAnything: {
                performCompanionAction {
                    onAskAI(nil)
                }
            },
            onQuickCapture: {
                performCompanionAction {
                    isShowingCommandBar = true
                }
            },
            onReviewTodos: {
                performCompanionAction(action: onReviewTodos)
            }
        )
    }

    private var companionAccessibilityLabel: String {
        if isAIWorking {
            return "Notebook companion, checking your notebook"
        }
        if companionSnapshot.attentionCount > 0 {
            return "Notebook companion, \(companionSnapshot.attentionCount) overdue items"
        }
        return "Notebook companion"
    }

    private var combinedGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Start long press task on first touch
                if longPressTask == nil && !isPieMenuExpanded {
                    isPressed = true
                    startLongPressTask()
                }

                dragTranslation = value.translation
                let distance = hypot(value.translation.width, value.translation.height)

                // Cancel long press if user drags too far
                if distance >= 10 && !isPieMenuExpanded {
                    longPressTask?.cancel()
                    longPressTask = nil
                }

                // If pie menu is expanded, track which segment is highlighted
                if isPieMenuExpanded {
                    updateHighlightedAction(translation: value.translation)
                } else if distance >= 2 && longPressTask == nil {
                    // Regular drag to reposition (only if not waiting for long press)
                    self.offset = CGSize(
                        width: savedOffsetX + value.translation.width,
                        height: savedOffsetY + value.translation.height
                    )
                }
            }
            .onEnded { value in
                isPressed = false
                longPressTask?.cancel()
                longPressTask = nil
                let distance = hypot(value.translation.width, value.translation.height)

                if isPieMenuExpanded {
                    // Handle pie menu selection
                    if let action = highlightedAction {
                        executeAction(action)
                    }

                    // Close pie menu
                    adaptiveWithAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isPieMenuExpanded = false
                        highlightedAction = nil
                    }
                } else if distance < 2 {
                    // Simple tap - open the useful companion panel.
                    self.offset = CGSize(width: savedOffsetX, height: savedOffsetY)
                    openCompanion()
                } else {
                    // Drag ended - save new position
                    let finalOffset = CGSize(
                        width: savedOffsetX + value.translation.width,
                        height: savedOffsetY + value.translation.height
                    )
                    savedOffsetX = finalOffset.width
                    savedOffsetY = finalOffset.height

                    adaptiveWithAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
                        self.offset = finalOffset
                    }
                }

                dragTranslation = .zero
            }
    }

    private func startLongPressTask() {
        longPressTask = Task { @MainActor in
            do {
                try await Task.sleep(for: longPressDuration)

                // Check if still valid (not cancelled and finger hasn't moved)
                let distance = hypot(dragTranslation.width, dragTranslation.height)
                guard distance < 10 else { return }

                adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isPieMenuExpanded = true
                }

                // Haptic feedback
                #if os(iOS)
                let impact = UIImpactFeedbackGenerator(style: .medium)
                impact.impactOccurred()
                #endif
            } catch {
                // Task was cancelled
            }
        }
    }

    private func updateHighlightedAction(translation: CGSize) {
        let distance = hypot(translation.width, translation.height)

        // Only highlight if dragged far enough from center
        guard distance > 25 else {
            highlightedAction = nil
            return
        }

        let angle = normalizedDegrees(atan2(translation.height, translation.width) * 180 / .pi)

        // Data-driven segment detection
        for action in PieMenuAction.allCases {
            let start = normalizedDegrees(action.startAngle)
            let end = normalizedDegrees(action.endAngle)
            if angleInRange(angle, from: start, to: end) {
                highlightedAction = action
                return
            }
        }
    }

    private func executeAction(_ action: PieMenuAction) {
        #if os(iOS)
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        #endif

        switch action {
        case .newPresentation:
            onNewPresentation()
        case .newWorkItem:
            isShowingWorkItemSheet = true
        case .recordPractice:
            onRecordPractice()
        case .newTodo:
            onNewTodo()
        case .newNote:
            onNewNote()
        }
    }

    private func openCompanion() {
        onRefreshCompanion()
        isCompanionPresented = true
    }

    private func performCompanionAction(action: @escaping () -> Void) {
        isCompanionPresented = false
        action()
    }

    private func normalizedDegrees(_ angle: Double) -> Double {
        angle < 0 ? angle + 360 : angle
    }

    private func angleInRange(_ angle: Double, from start: Double, to end: Double) -> Bool {
        if start <= end {
            return angle >= start && angle < end
        }
        return angle >= start || angle < end
    }

    private func orbitOffset(for index: Int, radius: CGFloat) -> CGSize {
        let angle = Double(index) * (360.0 / 6.0)
        let radians = angle * .pi / 180
        return CGSize(width: cos(radians) * radius, height: sin(radians) * radius)
    }
}
