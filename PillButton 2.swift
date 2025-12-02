import SwiftUI

struct PillNavButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: AppTheme.FontSize.body, weight: .semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(minHeight: 30)
                .background(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.platformBackground))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
