// GoingOutStatusBadge.swift
// Colored capsule badge showing going-out status.

import SwiftUI

struct GoingOutStatusBadge: View {
    let status: GoingOutStatus

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.icon)
                .font(.system(size: 9))
            Text(status.displayName)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(status.color.opacity(0.12))
        )
    }
}
