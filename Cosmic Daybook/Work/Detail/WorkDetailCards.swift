import SwiftUI

// MARK: - Section Components

struct DetailSectionCard<Content: View, Trailing: View>: View {
    let title: String
    let icon: String
    let accentColor: Color
    var trailing: (() -> Trailing)?
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        icon: String,
        accentColor: Color,
        trailing: (() -> Trailing)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) where Trailing == EmptyView {
        self.title = title
        self.icon = icon
        self.accentColor = accentColor
        self.trailing = nil
        self.content = content
    }

    init(
        title: String,
        icon: String,
        accentColor: Color,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.accentColor = accentColor
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label {
                    Text(title)
                        .font(AppTheme.ScaledFont.bodyBold)
                } icon: {
                    Image(systemName: icon)
                        .foregroundStyle(accentColor)
                }

                Spacer()

                if let trailing {
                    trailing()
                }
            }

            content()
        }
        .padding(20)
        .surface(UIConstants.CornerRadius.extraLarge, fill: Color.primary.opacity(UIConstants.OpacityConstants.whisper))
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                Text(title)
                    .font(AppTheme.ScaledFont.bodySemibold)
                    .foregroundStyle(.primary)

                Text(subtitle)
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

struct ActionItemBox: View {
    let count: Int
    let label: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(count)")
                    .font(AppTheme.ScaledFont.calloutBold)
                    .foregroundStyle(.primary)

                Text(label)
                    .font(AppTheme.ScaledFont.captionSmall)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface(UIConstants.CornerRadius.control, fill: color.opacity(UIConstants.OpacityConstants.subtle))
    }
}
