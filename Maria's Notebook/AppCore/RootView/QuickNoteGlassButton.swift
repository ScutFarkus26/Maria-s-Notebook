// QuickNoteGlassButton.swift
// Floating action button for quick note creation

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

    @State private var offset: CGSize = .zero
    @State private var isPressed: Bool = false
    @State private var isPieMenuExpanded: Bool = false
    @State private var highlightedAction: PieMenuAction?
    @State private var dragTranslation: CGSize = .zero
    @State private var longPressTask: Task<Void, Never>?
    @State private var sparklePhase: Bool = false

    @AppStorage(UserDefaultsKeys.quickNoteButtonOffsetX) private var savedOffsetX: Double = 0
    @AppStorage(UserDefaultsKeys.quickNoteButtonOffsetY) private var savedOffsetY: Double = 0

    private let pieMenuRadius: CGFloat = 95
    private let longPressDuration: Duration = .milliseconds(400) // 0.4 seconds

    var body: some View {
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
        .accessibilityLabel("Quick command")
        .accessibilityHint(
            "Double tap to open command bar, hold for presentation,"
            + " work, practice, todo, and note actions, or drag to reposition"
        )
        .accessibilityAddTraits(.isButton)
    }

    private var pieMenuOverlay: some View {
        ZStack {
            Circle()
                .fill(
                    AngularGradient(
                        colors: [.cyan.opacity(0.4), .pink.opacity(0.4), .mint.opacity(0.4), .cyan.opacity(0.4)],
                        center: .center
                    )
                )
                .blur(radius: 12)
                .frame(width: pieMenuRadius * 2 + 26, height: pieMenuRadius * 2 + 26)
                .scaleEffect(sparklePhase ? 1.04 : 0.96)
                .opacity(0.95)
                .adaptiveAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: sparklePhase)

            ForEach(0..<6, id: \.self) { index in
                Image(systemName: "sparkle")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .offset(orbitOffset(for: index, radius: pieMenuRadius + 20))
                    .rotationEffect(.degrees(sparklePhase ? 360 : 0))
                    .opacity(0.8)
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
        Group {
            #if os(iOS)
            Image(systemName: isPieMenuExpanded ? "xmark" : "plus")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isPieMenuExpanded
                                    ? [.pink.opacity(0.9), .orange.opacity(0.9)]
                                    : [.blue.opacity(0.9), .teal.opacity(0.85)],
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
                    color: .black.opacity(UIConstants.OpacityConstants.statusBg),
                    radius: AppTheme.Spacing.xsmall,
                    x: 0,
                    y: AppTheme.Spacing.xxsmall
                )
                .rotationEffect(.degrees(isPieMenuExpanded ? 90 : 0))
            #else
            Image(systemName: isPieMenuExpanded ? "xmark" : "plus")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: isPieMenuExpanded
                                    ? [.pink.opacity(0.9), .orange.opacity(0.9)]
                                    : [.blue.opacity(0.9), .teal.opacity(0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                )
                .clipShape(Circle())
                .shadow(
                    color: .black.opacity(UIConstants.OpacityConstants.statusBg),
                    radius: AppTheme.Spacing.xsmall,
                    x: 0,
                    y: AppTheme.Spacing.xxsmall
                )
                .rotationEffect(.degrees(isPieMenuExpanded ? 90 : 0))
            #endif
        }
        .adaptiveAnimation(.spring(response: 0.3, dampingFraction: 0.7), value: isPieMenuExpanded)
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
                    _ = adaptiveWithAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isPieMenuExpanded = false
                        highlightedAction = nil
                    }
                } else if distance < 2 {
                    // Simple tap - open command bar
                    self.offset = CGSize(width: savedOffsetX, height: savedOffsetY)
                    isShowingCommandBar = true
                } else {
                    // Drag ended - save new position
                    let finalOffset = CGSize(
                        width: savedOffsetX + value.translation.width,
                        height: savedOffsetY + value.translation.height
                    )
                    savedOffsetX = finalOffset.width
                    savedOffsetY = finalOffset.height

                    _ = adaptiveWithAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
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

                _ = adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
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
