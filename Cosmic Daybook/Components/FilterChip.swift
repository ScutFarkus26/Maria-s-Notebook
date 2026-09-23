// FilterChip.swift
// The toggle chip the lesson and work filter bars share.
//
// Tinted at 0.15 with a 0.5 ring in the active colour while on; the faint
// label tint with secondary text while off. Lived in LessonsFilterChipBar
// until 2026-09-22, though WorkKindFilterChipBar already used it.

import SwiftUI

struct FilterChip: View {
    let label: String
    var icon: String?
    let isActive: Bool
    var activeColor: Color = .accentColor
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(label)
                    .font(AppTheme.ScaledFont.caption)
                    .fontWeight(isActive ? .semibold : .regular)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .capsuleFill(
                isActive
                    ? activeColor.opacity(UIConstants.OpacityConstants.accent)
                    : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)
            )
            .overlay(
                Capsule().stroke(
                    isActive ? activeColor.opacity(UIConstants.OpacityConstants.half) : Color.clear,
                    lineWidth: 1
                )
            )
            .foregroundStyle(isActive ? activeColor : .secondary)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }
}
