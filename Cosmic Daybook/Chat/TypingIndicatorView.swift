import SwiftUI

/// Animated bouncing dots indicator shown while the assistant is thinking.
/// Uses colorful dots with playful bounce. Respects Reduce Motion accessibility setting.
struct TypingIndicatorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var activeIndex = 0
    @State private var timer: Timer?
    /// Between `onAppear` and `onDisappear`. A row of a lazy stack can keep its
    /// views after scrolling away, and a window report must not restart the
    /// timer for dots nobody can reach.
    @State private var isAppeared = false
    /// Whether the window can be seen: the Mac's occlusion state, always true
    /// elsewhere.
    @State private var isWindowVisible = true

    private let dotCount = 3
    private let dotSize: CGFloat = 10
    private let bounceHeight: CGFloat = -10
    private let dotColors: [Color] = [.pink, .purple, .blue]

    var body: some View {
        HStack(spacing: AppTheme.Spacing.small) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(dotColors[index])
                    .frame(width: dotSize, height: dotSize)
                    .scaleEffect(activeIndex == index ? 1.3 : 1.0)
                    .offset(y: reduceMotion ? 0 : (activeIndex == index ? bounceHeight : 0))
            }
        }
        .accessibilityLabel("Assistant is thinking")
        .onAppear {
            isAppeared = true
            updateBouncing(in: scenePhase)
        }
        .onDisappear {
            isAppeared = false
            stopBouncing()
        }
        // Nobody sees the dots while the scene is inactive or in the
        // background (e.g. the app left thinking behind another window), so
        // stop waking the CPU until it is active again.
        .onChange(of: scenePhase) { _, phase in
            updateBouncing(in: phase)
        }
        // Nor while the Mac window is minimized, covered or on another Space,
        // which leaves `scenePhase` active.
        .onWindowVisibilityChange { visible in
            isWindowVisible = visible
            updateBouncing(in: scenePhase)
        }
    }

    /// Bounces only while the dots can be seen: on screen, in an active scene,
    /// in a window someone can see, and with motion allowed.
    private func updateBouncing(in phase: ScenePhase) {
        if isAppeared, phase == .active, isWindowVisible, !reduceMotion {
            startBouncing()
        } else {
            stopBouncing()
        }
    }

    private func stopBouncing() {
        timer?.invalidate()
        timer = nil
    }

    private func startBouncing() {
        // `onAppear` can fire more than once without a matching `onDisappear`
        // (re-parenting, sheet re-presentation); without this guard the previous
        // timer is dropped un-invalidated and keeps waking the CPU forever.
        guard timer == nil else { return }
        let bounceTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    activeIndex = (activeIndex + 1) % dotCount
                }
            }
        }
        // Let the system coalesce this wake with other work — a decorative dot
        // animation doesn't need a precise fire time.
        bounceTimer.tolerance = 0.1
        timer = bounceTimer
    }
}
