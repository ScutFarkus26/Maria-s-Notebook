import SwiftUI

struct PillNavButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    private var backgroundStyle: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor)
        } else {
            // Cross-platform neutral background (matches PillButton.swift)
            return AnyShapeStyle(Color.primary.opacity(0.08))
        }
    }

    private var foregroundStyle: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.white)
        } else {
            return AnyShapeStyle(Color.primary)
        }
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: AppTheme.FontSize.body, weight: .semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(minHeight: 30)
                .background(backgroundStyle)
                .foregroundStyle(foregroundStyle)
                .overlay(
                    Capsule()
                        .stroke(Color.primary.opacity(isSelected ? 0.0 : 0.10), lineWidth: 1)
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    VStack(spacing: 12) {
        PillNavButton(title: "Overview", isSelected: true) {}
        PillNavButton(title: "Checklist", isSelected: false) {}
    }
    .padding()
}
