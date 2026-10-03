import SwiftUI

// MARK: - Compact Grid Card

struct CompactGridCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .cardStyle(cornerRadius: AppTheme.Spacing.small + 2, padding: SettingsStyle.compactPadding)
    }
}
