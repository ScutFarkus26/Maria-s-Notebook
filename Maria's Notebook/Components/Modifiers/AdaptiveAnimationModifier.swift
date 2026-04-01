// AdaptiveAnimationModifier.swift
// Respects the user's Reduce Motion accessibility setting

import SwiftUI

#if os(iOS)
import UIKit
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
@MainActor
func adaptiveWithAnimation<Result>(_ animation: Animation? = .default, _ body: () throws -> Result) rethrows -> Result {
    #if os(iOS)
    if UIAccessibility.isReduceMotionEnabled {
        return try body()
    }
    #endif
    return try withAnimation(animation, body)
}
