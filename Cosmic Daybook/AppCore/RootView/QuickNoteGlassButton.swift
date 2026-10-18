// QuickNoteGlassButton.swift
// Floating quick-capture button. A tap opens quick capture — the one capture
// surface; a long press fans out the radial menu of the five create actions
// (slide onto one and let go); a drag moves the button. On macOS a right-click
// lists the same five actions.

import SwiftUI

// Isolated component to prevent RootView re-renders during drag.
// swiftlint:disable:next type_body_length
struct QuickNoteGlassButton: View {
    @Binding var isShowingCommandBar: Bool
    var onNewPresentation: () -> Void
    @Binding var isShowingWorkItemSheet: Bool
    var onRecordPractice: () -> Void
    var onNewTodo: () -> Void
    var onNewNote: () -> Void

    @State private var offset: CGSize = .zero
    /// The finger's travel from where it went down; nil while no finger is.
    /// Gesture state, so a press the system cancels (a sheet coming up, a
    /// call) ends here as surely as lifting the finger: `onEnded` never runs
    /// for a cancelled press (bug hunt 2026-10-17 #38).
    @GestureState private var press: CGSize? = nil // swiftlint:disable:this implicit_optional_initialization
    /// This press has dragged the button: once past the long-press slop it
    /// stays a move, even back over where it started.
    @State private var hasMoved = false
    @State private var isPieMenuExpanded: Bool = false
    @State private var highlightedAction: PieMenuAction?
    @State private var longPressTask: Task<Void, Never>?
    @State private var sparklePhase: Bool = false
    /// The area the button floats over, for keeping it inside the window.
    @State private var containerSize: CGSize = .zero

    @AppStorage(UserDefaultsKeys.quickNoteButtonOffsetX) private var savedOffsetX: Double = 0
    @AppStorage(UserDefaultsKeys.quickNoteButtonOffsetY) private var savedOffsetY: Double = 0

    private let pieMenuRadius: CGFloat = 95
    private let longPressDuration: Duration = .milliseconds(400) // 0.4 seconds

    var body: some View {
        accessibleContent
            // Fills the overlay only to measure it (an empty frame takes no
            // touches), so a narrowed Mac window or a rotated iPad pulls a
            // dragged-away button back into reach.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .onGeometryChange(for: CGSize.self, of: Self.size(of:), action: measureContainer)
    }

    nonisolated private static func size(of proxy: GeometryProxy) -> CGSize { proxy.size }

    private func measureContainer(_ size: CGSize) {
        containerSize = size
        pullBackIntoView()
    }

    private var labeledContent: some View {
        pointerContent
            .accessibilityLabel("Quick capture")
            .accessibilityHint("Opens quick capture")
            .accessibilityAddTraits(.isButton)
    }

    private var accessibleContent: some View {
        labeledContent
        // The long-press menu and the drag are unreachable by assistive tech,
        // so every action is also in the VoiceOver actions rotor.
        .accessibilityAction(named: "Quick Capture") { isShowingCommandBar = true }
        .accessibilityAction(named: PieMenuAction.newPresentation.label) { perform(.newPresentation) }
        .accessibilityAction(named: PieMenuAction.newWorkItem.label) { perform(.newWorkItem) }
        .accessibilityAction(named: PieMenuAction.recordPractice.label) { perform(.recordPractice) }
        .accessibilityAction(named: PieMenuAction.newTodo.label) { perform(.newTodo) }
        .accessibilityAction(named: PieMenuAction.newNote.label) { perform(.newNote) }
    }

    private var floatingContent: some View {
        // Main button with fixed size
        visualContent
            .scaleEffect(press != nil && !isPieMenuExpanded ? 0.92 : 1.0)
            .adaptiveAnimation(.easeInOut(duration: 0.1), value: press != nil)
            .overlay {
                // Pie menu segments overlay (doesn't affect button layout)
                if isPieMenuExpanded {
                    pieMenuOverlay
                }
            }
        .offset(offset)
        .padding(.trailing, Self.trailingInset)
        .padding(.bottom, Self.bottomInset)
        .gesture(combinedGesture)
        .onChange(of: press == nil) { _, isUp in
            if isUp {
                pressEnded()
            } else {
                startLongPressTask()
            }
        }
        .onAppear {
            self.offset = restingOffset
        }
        .onChange(of: isPieMenuExpanded) { _, expanded in
            sparklePhase = expanded
        }
        .onDisappear {
            longPressTask?.cancel()
        }
    }

    @ViewBuilder
    private var pointerContent: some View {
        // macOS: a standard right-click menu gives pointer users the five
        // create actions without the press-and-slide.
        #if os(macOS)
        floatingContent
            .contextMenu {
                ForEach(PieMenuAction.allCases, id: \.self) { action in
                    Button {
                        perform(action)
                    } label: {
                        Label(action.label, systemImage: action.icon)
                    }
                }
            }
            .help("Quick capture — hold or right-click for create actions")
        #else
        floatingContent
        #endif
    }

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
                    .offset(Self.orbitOffset(for: index, radius: pieMenuRadius + 20))
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
        Image(systemName: isPieMenuExpanded ? "xmark" : "plus")
            .font(.system(size: 24, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .background(
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isPieMenuExpanded
                                ? [
                                    .pink.opacity(UIConstants.OpacityConstants.almostOpaque),
                                    .orange.opacity(UIConstants.OpacityConstants.almostOpaque)
                                ]
                                : [
                                    .blue.opacity(UIConstants.OpacityConstants.almostOpaque),
                                    .teal.opacity(UIConstants.OpacityConstants.nearSolid)
                                ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Circle()
                    .strokeBorder(
                        Color.white.opacity(UIConstants.OpacityConstants.light),
                        lineWidth: UIConstants.StrokeWidth.thin
                    )
            )
            .clipShape(Circle())
            .shadow(
                color: .black.opacity(UIConstants.OpacityConstants.muted),
                radius: AppTheme.Spacing.xsmall,
                x: 0,
                y: AppTheme.Spacing.xxsmall
            )
            .rotationEffect(.degrees(isPieMenuExpanded ? 90 : 0))
            .contentShape(Circle())
            .adaptiveAnimation(.spring(response: 0.3, dampingFraction: 0.7), value: isPieMenuExpanded)
    }

    private var combinedGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .updating($press) { value, press, _ in
                press = value.translation
            }
            .onChanged { value in
                // If pie menu is expanded, track which segment is highlighted
                if isPieMenuExpanded {
                    updateHighlightedAction(translation: value.translation)
                } else if !QuickNoteButtonPress.isTap(value.translation, hasMoved: hasMoved) {
                    // Past the long-press slop: a drag that moves the button,
                    // for the rest of this press. Under it, still a tap
                    // (bug hunt 2026-10-17 #34).
                    hasMoved = true
                    longPressTask?.cancel()
                    self.offset = clamped(CGSize(
                        width: restingOffset.width + value.translation.width,
                        height: restingOffset.height + value.translation.height
                    ))
                }
            }
            .onEnded { value in
                longPressTask?.cancel()
                longPressTask = nil
                defer { hasMoved = false }

                if isPieMenuExpanded {
                    // Handle pie menu selection; letting go off every segment just closes it
                    if let action = highlightedAction {
                        perform(action)
                    }

                    adaptiveWithAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isPieMenuExpanded = false
                        highlightedAction = nil
                    }
                } else if QuickNoteButtonPress.isTap(value.translation, hasMoved: hasMoved) {
                    // A plain tap is the one capture surface.
                    self.offset = restingOffset
                    isShowingCommandBar = true
                } else {
                    // Drag ended - save new position, inside the window
                    let finalOffset = clamped(CGSize(
                        width: restingOffset.width + value.translation.width,
                        height: restingOffset.height + value.translation.height
                    ))
                    savedOffsetX = finalOffset.width
                    savedOffsetY = finalOffset.height

                    adaptiveWithAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
                        self.offset = finalOffset
                    }
                }
            }
    }

    /// Starts the long press when a finger goes down.
    private func startLongPressTask() {
        longPressTask?.cancel()
        longPressTask = Task {
            do {
                try await Task.sleep(for: longPressDuration)

                // Only for a finger still down that hasn't dragged the button.
                guard !isPieMenuExpanded,
                      QuickNoteButtonPress.opensMenu(translation: press, hasMoved: hasMoved) else { return }

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

    /// The finger is up: lifted, or the press was cancelled. A cancelled press
    /// never reaches `onEnded`, so it's tidied here — a turn later, after any
    /// `onEnded` that did run: the menu closes with nothing chosen and a
    /// half-dragged button goes back to where it rests.
    private func pressEnded() {
        longPressTask?.cancel()
        longPressTask = nil
        Task {
            guard press == nil else { return }
            hasMoved = false
            if isPieMenuExpanded {
                adaptiveWithAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isPieMenuExpanded = false
                    highlightedAction = nil
                }
            }
            pullBackIntoView()
        }
    }

    private func updateHighlightedAction(translation: CGSize) {
        let distance = hypot(translation.width, translation.height)

        // Only highlight if dragged far enough from center
        guard distance > 25 else {
            highlightedAction = nil
            return
        }

        let angle = Self.normalizedDegrees(atan2(translation.height, translation.width) * 180 / .pi)

        for action in PieMenuAction.allCases {
            let start = Self.normalizedDegrees(action.startAngle)
            let end = Self.normalizedDegrees(action.endAngle)
            if Self.angleInRange(angle, from: start, to: end) {
                if highlightedAction != action {
                    highlightedAction = action
                }
                return
            }
        }
    }

    /// Runs one of the five create actions.
    private func perform(_ action: PieMenuAction) {
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

    /// `offset` kept inside the measured window; unchanged before it is measured.
    private func clamped(_ offset: CGSize) -> CGSize {
        guard containerSize.width > 0, containerSize.height > 0 else { return offset }
        return Self.clampedOffset(
            offset, in: containerSize, buttonSize: Self.buttonSize,
            trailingInset: Self.trailingInset, bottomInset: Self.bottomInset
        )
    }

    /// Where the button rests: the saved position, kept inside this window.
    private var restingOffset: CGSize {
        clamped(CGSize(width: savedOffsetX, height: savedOffsetY))
    }

    /// Shows a saved position that is now outside the window inside it. Only the
    /// drawn offset moves: the saved one is the guide's, shared by every window,
    /// and a keyboard or a narrow window mustn't overwrite it (review 2026-10-11
    /// (c) #4). Left alone mid-drag.
    private func pullBackIntoView() {
        guard press == nil else { return }
        let inside = restingOffset
        if offset != inside {
            offset = inside
        }
    }
}
