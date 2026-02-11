// QuickNoteGlassButton.swift
// Floating action button for quick note creation

import SwiftUI

/// Isolated component to prevent RootView re-renders during drag
struct QuickNoteGlassButton: View {
    @Binding var isShowingSheet: Bool
    @Binding var isShowingPresentationSheet: Bool
    @Binding var isShowingWorkItemSheet: Bool

    @State private var offset: CGSize = .zero
    @State private var isPressed: Bool = false
    @State private var isPieMenuExpanded: Bool = false
    @State private var highlightedAction: PieMenuAction? = nil
    @State private var dragTranslation: CGSize = .zero
    @State private var longPressTask: Task<Void, Never>? = nil

    @AppStorage("QuickNoteButton.offsetX") private var savedOffsetX: Double = 0
    @AppStorage("QuickNoteButton.offsetY") private var savedOffsetY: Double = 0

    private let pieMenuRadius: CGFloat = 95
    private let longPressDuration: Duration = .milliseconds(400) // 0.4 seconds

    var body: some View {
        // Main button with fixed size
        visualContent
            .scaleEffect(isPressed && !isPieMenuExpanded ? 0.92 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .overlay {
                // Pie menu segments overlay (doesn't affect button layout)
                if isPieMenuExpanded {
                    pieMenuOverlay
                }
            }
        .offset(offset)
        .padding(.trailing, 20)
        #if os(iOS)
        .padding(.bottom, 85)
        #else
        .padding(.bottom, 40)
        #endif
        .gesture(combinedGesture)
        .onAppear {
            self.offset = CGSize(width: savedOffsetX, height: savedOffsetY)
        }
        .onDisappear {
            longPressTask?.cancel()
        }
        .accessibilityLabel("Add quick note")
        .accessibilityHint("Double tap to open note editor, hold to see more options, or drag to reposition")
        .accessibilityAddTraits(.isButton)
    }

    private var pieMenuOverlay: some View {
        ZStack {
            // Top segment - New Presentation
            PieMenuSegment(
                action: .newPresentation,
                isTop: true,
                isExpanded: isPieMenuExpanded,
                isHighlighted: highlightedAction == .newPresentation,
                radius: pieMenuRadius
            )

            // Bottom segment - New Work Item
            PieMenuSegment(
                action: .newWorkItem,
                isTop: false,
                isExpanded: isPieMenuExpanded,
                isHighlighted: highlightedAction == .newWorkItem,
                radius: pieMenuRadius
            )
        }
        .background(
            Circle()
                .fill(.ultraThinMaterial)
                .frame(width: pieMenuRadius * 2 + 20, height: pieMenuRadius * 2 + 20)
                .opacity(isPieMenuExpanded ? 1.0 : 0.0)
        )
    }

    private var visualContent: some View {
        Group {
            #if os(iOS)
            Image(systemName: isPieMenuExpanded ? "xmark" : "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                )
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .rotationEffect(.degrees(isPieMenuExpanded ? 90 : 0))
            #else
            Image(systemName: isPieMenuExpanded ? "xmark" : "plus")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.accentColor)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                .rotationEffect(.degrees(isPieMenuExpanded ? 90 : 0))
            #endif
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPieMenuExpanded)
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
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                        isPieMenuExpanded = false
                        highlightedAction = nil
                    }
                } else if distance < 2 {
                    // Simple tap - open quick note sheet
                    self.offset = CGSize(width: savedOffsetX, height: savedOffsetY)
                    isShowingSheet = true
                } else {
                    // Drag ended - save new position
                    let finalOffset = CGSize(
                        width: savedOffsetX + value.translation.width,
                        height: savedOffsetY + value.translation.height
                    )
                    savedOffsetX = finalOffset.width
                    savedOffsetY = finalOffset.height

                    withAnimation(.snappy(duration: 0.25, extraBounce: 0)) {
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

                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
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

        // Determine which segment based on vertical position
        // Top half = presentation, Bottom half = work item
        if translation.height < 0 {
            highlightedAction = .newPresentation
        } else {
            highlightedAction = .newWorkItem
        }
    }

    private func executeAction(_ action: PieMenuAction) {
        #if os(iOS)
        let impact = UIImpactFeedbackGenerator(style: .light)
        impact.impactOccurred()
        #endif

        switch action {
        case .newPresentation:
            isShowingPresentationSheet = true
        case .newWorkItem:
            isShowingWorkItemSheet = true
        }
    }
}
