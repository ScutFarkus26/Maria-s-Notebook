import SwiftUI

/// The presentation sheet's header: the lesson, where it sits, when it is
/// planned or was given, and a ⋯ menu for everything about planning it.
struct PresentationHeaderBand<MenuItems: View>: View {
    let lessonName: String
    let area: String
    let sequence: String
    let areaColor: Color
    let statusLine: String
    var onTapTitle: (() -> Void)?
    @ViewBuilder let menuItems: MenuItems

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "book.closed.fill")
                .font(.title3)
                .foregroundStyle(areaColor)
                .frame(width: 44, height: 44)
                .background(
                    areaColor.opacity(UIConstants.OpacityConstants.accent),
                    in: RoundedRectangle(cornerRadius: UIConstants.CornerRadius.large, style: .continuous)
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                if !placeLine.isEmpty {
                    Text(placeLine)
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(areaColor)
                }
                title
                Text(statusLine)
                    .font(AppTheme.ScaledFont.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 30, height: 30)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var placeLine: String {
        [area.trimmed(), sequence.trimmed()].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    @ViewBuilder
    private var title: some View {
        if let onTapTitle {
            Button(action: onTapTitle) {
                Text(lessonName)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .help("Open the lesson's Pages file")
            .accessibilityHint("Opens the lesson's Pages file")
        } else {
            Text(lessonName)
                .font(.title2.weight(.bold))
        }
    }
}
