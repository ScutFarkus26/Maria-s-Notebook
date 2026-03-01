import SwiftUI

/// A reusable pill-shaped button that can be selected or unselected
/// Used across the app for status, kind, outcome, and category selections
struct SelectablePillButton<T: Hashable>: View {
    let item: T
    let isSelected: Bool
    let color: Color
    let icon: String
    let label: String
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(AppTheme.ScaledFont.captionSemibold)
            }
            .foregroundStyle(isSelected ? .white : color)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(isSelected ? color : color.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .stroke(color.opacity(isSelected ? 0 : 0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
