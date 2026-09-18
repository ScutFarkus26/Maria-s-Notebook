import SwiftUI

/// Reusable theme chip — used inside cards, the detail pane, and the filter bar.
struct StoryThemeChip: View {
    enum Variant {
        case display
        case selectable(isSelected: Bool, action: () -> Void)
        case removable(action: () -> Void)
    }

    let label: String
    let variant: Variant

    init(_ label: String, variant: Variant = .display) {
        self.label = label
        self.variant = variant
    }

    var body: some View {
        switch variant {
        case .display:
            chipBody(isSelected: false)
        case .selectable(let isSelected, let action):
            Button(action: action) {
                chipBody(isSelected: isSelected)
            }
            .buttonStyle(.plain)
        case .removable(let action):
            HStack(spacing: 4) {
                chipText
                Button(action: action) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(label)")
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule().fill(Color.secondary.opacity(0.12))
            )
        }
    }

    private var chipText: some View {
        Text(label)
            .font(.caption)
            .lineLimit(1)
    }

    private func chipBody(isSelected: Bool) -> some View {
        chipText
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .background(
                Capsule()
                    .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.12))
            )
    }
}
