import SwiftUI

// MARK: - Settings Celebration

/// A quiet one-shot celebration: a handful of small stars float out and fade for about
/// a second each time `trigger` turns true (the first backup ever, "All set" on the
/// Overview). Under Reduce Motion a soft checkmark fades in and out instead.
///
/// The burst runs as one animation and removes itself in that animation's completion,
/// so nothing (no timer, no repeating animation) is left running once it has finished.
struct SettingsCelebrationModifier: ViewModifier {
    let trigger: Bool

    /// Bumped once per celebration; the burst is keyed on it so each one starts fresh.
    @State private var burst = 0
    @State private var isCelebrating = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if isCelebrating {
                    SettingsCelebrationBurst { isCelebrating = false }
                        .id(burst)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .onChange(of: trigger) { wasOn, isOn in
                guard isOn, !wasOn else { return }
                burst += 1
                isCelebrating = true
            }
    }
}

extension View {
    /// Plays a quiet one-shot celebration over this view each time `trigger` turns true.
    func settingsCelebration(trigger: Bool) -> some View {
        modifier(SettingsCelebrationModifier(trigger: trigger))
    }
}

// MARK: - Burst

private struct SettingsCelebrationBurst: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let onFinish: () -> Void

    @State private var progress: CGFloat = 0

    private static let particleCount = 8
    private static let colors: [Color] = [.yellow, AppColors.info, .pink, AppColors.success, .purple]

    var body: some View {
        ZStack {
            if reduceMotion {
                checkmark
            } else {
                ForEach(0..<Self.particleCount, id: \.self) { index in
                    particle(index)
                }
            }
        }
        .onAppear(perform: start)
    }

    private var checkmark: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.title2)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(AppColors.success)
            // Fades in over the first half, back out over the second; opacity only, no motion.
            .opacity(progress < 0.5 ? progress * 2 : (1 - progress) * 2)
    }

    private func particle(_ index: Int) -> some View {
        let angle = (Double(index) / Double(Self.particleCount)) * 2 * .pi + (index.isMultiple(of: 2) ? 0 : 0.3)
        let distance: CGFloat = index.isMultiple(of: 2) ? 34 : 24
        return Image(systemName: index.isMultiple(of: 3) ? "sparkle" : "star.fill")
            .font(.caption2)
            .foregroundStyle(Self.colors[index % Self.colors.count])
            .scaleEffect(0.4 + 0.6 * (1 - progress))
            .offset(
                x: cos(angle) * distance * progress,
                y: sin(angle) * distance * progress
            )
            .opacity(Double(1 - progress))
    }

    private func start() {
        if reduceMotion {
            // A linear ramp drives the fade in and back out; `adaptiveWithAnimation` would
            // skip it under Reduce Motion, and a fade is not motion.
            withAnimation(.linear(duration: 1.2)) {
                progress = 1
            } completion: {
                onFinish()
            }
        } else {
            withAnimation(.easeOut(duration: 1.0)) {
                progress = 1
            } completion: {
                onFinish()
            }
        }
    }
}

// MARK: - Preview

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct SettingsCelebrationPreview: View {
    @State private var done = false

    var body: some View {
        Button(done ? "All set" : "Finish") { done.toggle() }
            .buttonStyle(.borderedProminent)
            .settingsCelebration(trigger: done)
            .padding(AppTheme.Spacing.xlarge)
    }
}

#Preview {
    SettingsCelebrationPreview()
}
