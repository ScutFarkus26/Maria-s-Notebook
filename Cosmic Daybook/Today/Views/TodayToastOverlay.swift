// TodayToastOverlay.swift
// Today's brief confirmation ("Marked presented", "Bumped to tomorrow").
//
// A view of its own that takes the toast state as a binding: TodayView passes
// `$toastMessage` without reading it, so a toast appearing and clearing again
// re-runs this small body instead of every section of Today. Same look and
// timing as before; `TodayView.toast(_:)` still owns the message and its
// two-second dismissal.

import SwiftUI

struct TodayToastOverlay: View {
    @Binding var message: String?

    var body: some View {
        if let message {
            Text(message)
                .font(AppTheme.ScaledFont.captionSemibold)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .surface(
                    UIConstants.CornerRadius.control,
                    fill: Color.black.opacity(UIConstants.OpacityConstants.nearSolid),
                    style: .continuous
                )
                .foregroundStyle(.white)
                .shadow(color: Color.black.opacity(UIConstants.OpacityConstants.moderate), radius: 6, x: 0, y: 3)
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding(.top, 8)
        }
    }
}
