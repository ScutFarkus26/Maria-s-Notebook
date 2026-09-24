import SwiftUI

// MARK: - Bobbing Animation Modifier

/// A reusable view modifier for bobbing animation that respects scene phase
struct BobbingAnimationModifier: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @Binding var bob: Bool
    let duration: Double
    let offset: CGFloat

    init(bob: Binding<Bool>, duration: Double = 1.6, offset: CGFloat = 2) {
        self._bob = bob
        self.duration = duration
        self.offset = offset
    }

    private var isAnimating: Bool {
        #if os(macOS)
        false
        #else
        scenePhase == .active
        #endif
    }

    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        content
            .offset(y: bob ? -offset : offset)
            .adaptiveAnimation(
                isAnimating ? .easeInOut(duration: duration).repeatCount(60, autoreverses: true) : nil,
                value: bob
            )
            .onAppear { bob = true }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    bob = true
                } else {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        bob = false
                    }
                }
            }
        #endif
    }
}

extension View {
    /// Applies a bobbing animation that respects scene phase for energy efficiency
    func bobbingAnimation(bob: Binding<Bool>, duration: Double = 1.6, offset: CGFloat = 2) -> some View {
        modifier(BobbingAnimationModifier(bob: bob, duration: duration, offset: offset))
    }

    /// Avoid offscreen rasterization on macOS where the student card grids can
    /// create sustained RenderBox pressure during navigation and layout.
    @ViewBuilder
    func studentCardRasterization() -> some View {
        #if os(macOS)
        self
        #else
        self.drawingGroup()
        #endif
    }
}
