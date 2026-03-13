// ObservationTimerView.swift
// Timer display for observation duration with start/stop toggle.

import SwiftUI

struct ObservationTimerView: View {
    let elapsedSeconds: Int
    let isRunning: Bool
    let onToggle: () -> Void

    private var formattedTime: String {
        let minutes = elapsedSeconds / 60
        let seconds = elapsedSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var body: some View {
        HStack(spacing: 10) {
            // Timer display
            Text(formattedTime)
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.semibold)
                .foregroundStyle(isRunning ? .primary : .secondary)
                .contentTransition(.numericText())

            // Start/Stop button
            Button {
                onToggle()
            } label: {
                Image(systemName: isRunning ? "pause.circle.fill" : "play.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isRunning ? AppColors.warning : AppColors.success)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}
