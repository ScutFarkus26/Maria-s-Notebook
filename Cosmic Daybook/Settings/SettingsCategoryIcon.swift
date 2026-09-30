import SwiftUI

// MARK: - Settings Category Icon

/// A category's symbol on a small colored tile, as system Settings draws them:
/// in the sidebar, and larger beside the open pane's title.
struct SettingsCategoryIcon: View {
    let category: SettingsCategory
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: category.icon)
            .font(.system(size: size * 0.58, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Self.tint(for: category).gradient,
                in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    /// One color per category, so each is easy to find again at a glance.
    static func tint(for category: SettingsCategory) -> Color {
        switch category {
        case .overview: return .orange
        case .schoolYear: return .red
        case .classroom: return .green
        case .lookAndFeel: return .pink
        case .messages: return .brown
        case .templates: return .purple
        case .connections: return .cyan
        case .intelligence: return .indigo
        case .syncBackup: return .blue
        case .troubleshooting: return .gray
        }
    }
}
