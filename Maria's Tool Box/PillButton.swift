import SwiftUI

public struct PillButton: View {
    public var title: String
    public var isSelected: Bool
    public var action: () -> Void

    public init(title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    private var backgroundStyle: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.accentColor)
        } else {
            return AnyShapeStyle(Color.platformBackground)
        }
    }

    private var foregroundStyle: some ShapeStyle {
        if isSelected {
            return AnyShapeStyle(Color.white)
        } else {
            return AnyShapeStyle(Color.primary)
        }
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: AppTheme.FontSize.body, weight: .semibold))
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
                .frame(minHeight: 30)
                .background(backgroundStyle)
                .foregroundStyle(foregroundStyle)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
