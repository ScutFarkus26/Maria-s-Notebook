// View+ConditionalModifiers.swift
// Shared conditional view modifiers

import SwiftUI

extension View {
    /// Applies a transformation when the condition is true.
    /// - Parameters:
    ///   - condition: The condition to check
    ///   - transform: The transformation to apply when condition is true
    /// - Returns: Either the transformed view or the original view
    @ViewBuilder
    func when<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }

    /// Disables animation when the condition is true.
    /// - Parameter condition: When true, animation is disabled
    /// - Returns: View with conditional animation
    func disableAnimation(when condition: Bool) -> some View {
        self.transaction { tx in
            if condition { tx.animation = nil }
        }
    }
}
