// JiggleModifier.swift
// iOS home-screen-style jiggle animation for reorder mode

import SwiftUI

/// Applies a subtle repeating rotation oscillation to a view, mimicking the iOS home screen jiggle.
/// When Reduce Motion is enabled, shows a dashed border instead of animating.
struct JiggleModifier: ViewModifier {
    let isActive: Bool
    let seed: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var jigglePhase = false

    /// Small offset derived from seed so adjacent items don't jiggle in sync
    private var seedOffset: Double {
        Double(abs(seed) % 7) * 0.015
    }

    private var angle: Double {
        jigglePhase ? 1.5 : -1.5
    }

    func body(content: Content) -> some View {
        if isActive {
            if reduceMotion {
                // Accessibility: static visual indicator instead of animation
                content
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(UIConstants.OpacityConstants.muted), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    )
            } else {
                content
                    .rotationEffect(.degrees(angle), anchor: .center)
                    .onAppear {
                        withAnimation(
                            .easeInOut(duration: 0.11 + seedOffset)
                            .repeatForever(autoreverses: true)
                        ) {
                            jigglePhase = true
                        }
                    }
                    .onDisappear {
                        jigglePhase = false
                    }
                    .onChange(of: isActive) { _, active in
                        if !active {
                            jigglePhase = false
                        }
                    }
            }
        } else {
            content
        }
    }
}

extension View {
    /// Applies iOS-style jiggle animation when active.
    /// - Parameters:
    ///   - isActive: Whether jiggle mode is on
    ///   - seed: Unique value per item for phase offset (use index or hash)
    func jiggle(isActive: Bool, seed: Int = 0) -> some View {
        modifier(JiggleModifier(isActive: isActive, seed: seed))
    }
}
