// AdaptiveAnimationModifier.swift
// Respects the user's Reduce Motion accessibility setting

import SwiftUI

#if os(iOS)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

/// A view modifier that conditionally applies animation based on the Reduce Motion setting
struct AdaptiveAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let animation: Animation?
    let value: V

    func body(content: Content) -> some View {
        content
            .animation(reduceMotion ? nil : animation, value: value)
    }
}

extension View {
    /// Applies animation that respects the Reduce Motion accessibility setting.
    /// When Reduce Motion is enabled, changes happen instantly without animation.
    func adaptiveAnimation<V: Equatable>(_ animation: Animation?, value: V) -> some View {
        modifier(AdaptiveAnimationModifier(animation: animation, value: value))
    }
}

/// Executes a closure with animation that respects the Reduce Motion setting.
/// When Reduce Motion is enabled, the closure executes without animation.
func adaptiveWithAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    #if os(iOS)
    if UIAccessibility.isReduceMotionEnabled {
        return try body()
    }
    #elseif os(macOS)
    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
        return try body()
    }
    #endif
    return try withAnimation(animation, body)
}

extension View {
    /// Spins the view one turn a second while `active` (not at all under Reduce Motion).
    ///
    /// Use this instead of a `repeatForever` animation keyed on a flag. Once such an
    /// animation starts, turning the flag off does not end it: SwiftUI keeps redrawing
    /// every frame for as long as the view is on screen, even though nothing visibly
    /// moves. Here the spinning view is a separate branch, so it goes away, animation
    /// and all, when `active` turns false.
    func spinning(while active: Bool) -> some View {
        modifier(SpinWhileActiveModifier(active: active))
    }
}

private struct SpinWhileActiveModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let active: Bool

    func body(content: Content) -> some View {
        if active && !reduceMotion {
            content.modifier(ContinuousSpinModifier())
        } else {
            content
        }
    }
}

private struct ContinuousSpinModifier: ViewModifier {
    @State private var angle: Double = 0

    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(angle))
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    angle = 360
                }
            }
    }
}
