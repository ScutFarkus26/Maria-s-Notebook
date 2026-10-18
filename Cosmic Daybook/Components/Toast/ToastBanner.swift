// ToastBanner.swift
// The brief confirmation a screen flashes after a bulk action.
//
// Both attendance screens — the Mac grid and the standalone sheet — say "All
// marked present" the same way, in the same place, for the same two seconds,
// and both had written it out. One banner means marking a class present never
// looks like two different features.

import OSLog
import SwiftUI

/// The banner itself: a dark rounded slab that drops in over the top edge.
struct ToastBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(AppTheme.ScaledFont.captionSemibold)
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.vertical, AppTheme.Spacing.small)
            .surface(
                UIConstants.CornerRadius.medium,
                fill: Color.black.opacity(UIConstants.OpacityConstants.nearSolid),
                style: .continuous
            )
            .foregroundStyle(.white)
            .shadow(color: Color.black.opacity(UIConstants.OpacityConstants.moderate), radius: 6, x: 0, y: 3)
            .transition(.move(edge: .top).combined(with: .opacity))
            .padding(.top, 8)
    }
}

extension View {
    /// Shows `message` over the top edge of this view while it is set.
    func toastBanner(_ message: String?) -> some View {
        overlay(alignment: .top) {
            if let message {
                ToastBanner(message: message)
            }
        }
    }

    /// Flashes `message` for two seconds (`duration`) and then clears it,
    /// animating both ends. The binding is the caller's own toast state.
    ///
    /// Clears only its own message: a newer toast shown meanwhile keeps its
    /// full time rather than going when this one's does (bug hunt 2026-10-17
    /// #38). The same words shown twice share the first one's time.
    func showToast(
        _ message: String, in toast: Binding<String?>, logger: Logger, duration: Duration = .seconds(2)
    ) {
        adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
            toast.wrappedValue = message
        }
        Task {
            do {
                try await Task.sleep(for: duration)
            } catch {
                logger.warning("Failed to sleep for toast dismissal: \(error)")
            }
            guard toast.wrappedValue == message else { return }
            adaptiveWithAnimation(.easeInOut(duration: 0.25)) {
                toast.wrappedValue = nil
            }
        }
    }
}
