import SwiftUI

/// Animated bouncing dots indicator shown while the assistant is thinking.
/// Uses colorful dots with playful bounce. Respects Reduce Motion accessibility setting.
struct TypingIndicatorView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var activeIndex = 0
    @State private var timer: Timer?

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
            guard !reduceMotion else { return }
            startBouncing()
        }
        .onDisappear {
            timer?.invalidate()
            timer = nil
        }
    }

    private func startBouncing() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { _ in
            Task { @MainActor in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.5)) {
                    activeIndex = (activeIndex + 1) % dotCount
                }
            }
        }
    }
}
