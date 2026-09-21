// QuickNoteGlassButton.swift
// Floating notebook companion. A tap opens quick capture — the one capture
// surface; a long press (right-click on macOS) opens the companion panel.
//
// Extensions:
// - QuickNoteGlassButton+Companion.swift (the panel, its context menu, placement)

import SwiftUI

// Isolated component to prevent RootView re-renders during drag.
// The stored state below is internal, not private, so the +Companion extension
// in the sibling file can read and clear it.
struct QuickNoteGlassButton: View {
    @AppStorage(UserDefaultsKeys.notebookCompanionVisible)
    var isNotebookCompanionVisible = true
    #if os(macOS)
    @Environment(\.openWindow) var openWindow
    @AppStorage(UserDefaultsKeys.notebookCompanionDetached)
    var isNotebookCompanionDetached = false
    #endif

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
    @State var isCompanionPresented: Bool = false
    /// Set when the 400 ms press fires, so the finger lift that follows is not
    /// also read as a tap (which would open capture behind the panel).
    @State private var didLongPress: Bool = false
    @State private var dragTranslation: CGSize = .zero
    @State private var longPressTask: Task<Void, Never>?

    @AppStorage(UserDefaultsKeys.quickNoteButtonOffsetX) private var savedOffsetX: Double = 0
    @AppStorage(UserDefaultsKeys.quickNoteButtonOffsetY) private var savedOffsetY: Double = 0

    private let longPressDuration: Duration = .milliseconds(400) // 0.4 seconds

    var body: some View {
        accessibilityContent
    }

    private var floatingContent: some View {
        // Main button with fixed size
        visualContent
            .scaleEffect(isPressed ? 0.92 : 1.0)
            .adaptiveAnimation(.easeInOut(duration: 0.1), value: isPressed)
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
        .onDisappear {
            longPressTask?.cancel()
        }
        .popover(isPresented: $isCompanionPresented, arrowEdge: .bottom) {
            companionPanel
        }
    }

    @ViewBuilder
    private var pointerContent: some View {
        // macOS: a left-click opens quick capture, so the companion actions and
        // the five create actions live on the standard right-click menu. On iOS
        // the long press opens the companion instead.
        #if os(macOS)
        floatingContent
            .contextMenu {
                companionContextMenu
            }
            .help("Quick capture — right-click for companion actions")
        #else
        floatingContent
        #endif
    }

    private var accessibilityContent: some View {
        pointerContent
        .accessibilityLabel(companionAccessibilityLabel)
        .accessibilityHint("Opens quick capture")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open Notebook Companion") { openCompanion() }
        .accessibilityAction(named: "Quick Capture") { isShowingCommandBar = true }
    }

    private var visualContent: some View {
        ZStack(alignment: .bottomTrailing) {
            NotebookCompanionCharacter(
                state: companionSnapshot.state(isWorking: isAIWorking)
            )

            if companionSnapshot.attentionCount > 0 {
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
    }

    private var combinedGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Start long press task on first touch
                if longPressTask == nil && !didLongPress {
                    isPressed = true
                    startLongPressTask()
                }

                dragTranslation = value.translation
                let distance = hypot(value.translation.width, value.translation.height)

                // Cancel long press if user drags too far
                if distance >= 10 {
                    longPressTask?.cancel()
                    longPressTask = nil
                }

                if distance >= 2 && longPressTask == nil && !didLongPress {
                    // Regular drag to reposition (only once the long press is off the table)
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
                dragTranslation = .zero

                let distance = hypot(value.translation.width, value.translation.height)
                let openedCompanion = didLongPress
                didLongPress = false

                if openedCompanion || distance < 2 {
                    self.offset = CGSize(width: savedOffsetX, height: savedOffsetY)
                    // A plain tap is the one capture surface; a long press has
                    // already opened the companion panel.
                    if !openedCompanion {
                        isShowingCommandBar = true
                    }
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
            }
    }

    private func startLongPressTask() {
        longPressTask = Task {
            do {
                try await Task.sleep(for: longPressDuration)

                // Check if still valid (not cancelled and finger hasn't moved)
                let distance = hypot(dragTranslation.width, dragTranslation.height)
                guard distance < 10 else { return }

                didLongPress = true
                openCompanion()

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

    /// Runs one of the five create actions. Reachable from the macOS
    /// right-click menu; on iOS the Today `+` menu and the command bar carry them.
    func perform(_ action: PieMenuAction) {
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
}
