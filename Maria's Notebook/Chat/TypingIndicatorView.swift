import SwiftUI

/// Animated bouncing dots indicator shown while the assistant is thinking.
/// Respects Reduce Motion accessibility setting.
struct TypingIndicatorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeIndex = 0
    @State private var timer: Timer?

    private let dotCount = 3
    private let dotSize: CGFloat = 8
    private let bounceHeight: CGFloat = -6

    var body: some View {
        HStack(spacing: AppTheme.Spacing.xsmall) {
            ForEach(0..<dotCount, id: \.self) { index in
                Circle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: dotSize, height: dotSize)
                    .offset(y: reduceMotion ? 0 : (activeIndex == index ? bounceHeight : 0))
            }
        }
        .accessibilityLabel("Assistant is thinking")
        .onAppear {
            guard !reduceMotion else { return }
            startBouncing()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func startBouncing() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(UIConstants.SpringAnimation.bouncy) {
                    activeIndex = (activeIndex + 1) % dotCount
                }
            }
        }
    }
}
