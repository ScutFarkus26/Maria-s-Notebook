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

    public var body: some View {
        var metrics = AppPill.Metrics()
        metrics.font = .system(size: AppTheme.FontSize.body, weight: .semibold)
        metrics.horizontalPadding = 20
        metrics.verticalPadding = 8
        metrics.minHeight = 30

        // Match agenda pill language for a unified look.
        return AppPillButton(title,
                             isSelected: isSelected,
                             selectionStyle: .accentOutline,
                             metrics: metrics,
                             action: action)
    }
}

