import SwiftUI

// MARK: - Reusable Button Components

/// State pill button showing status with icon and conditional highlighting
struct StatePill: View {
    let title: String
    let systemImage: String
    let tint: Color
    var active: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
            Text(title)
        }
        .font(.callout.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .foregroundStyle(tint)
        .capsuleFill(tint.opacity(active ? 0.20 : 0.10), style: .continuous)
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(tint.opacity(UIConstants.OpacityConstants.statusBg), lineWidth: 1)
        )
    }
}
