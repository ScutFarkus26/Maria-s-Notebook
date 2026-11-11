import SwiftUI

/// The presentation sheet's header: the lesson, where it sits, when it is
/// planned or was given, a Lesson Plan button when the lesson has a Pages
/// file, and a ⋯ menu for everything about planning it.
struct PresentationHeaderBand<MenuItems: View>: View {
    let lessonName: String
    let area: String
    let sequence: String
    let areaColor: Color
    let statusLine: String
    /// Opens the lesson's Pages file; nil when the lesson has none, which
    /// hides the button and leaves the title plain.
    var onOpenLessonPlan: (() -> Void)?
    @ViewBuilder let menuItems: MenuItems

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

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

            // On a narrow screen even an icon-only button wraps a short
            // lesson name (drawn at 390 points, 2026-11-10), so there the
            // plan opens from the title and the ⋯ menu, as before.
            HStack(spacing: 8) {
                if let onOpenLessonPlan, horizontalSizeClass != .compact {
                    lessonPlanButton(onOpenLessonPlan)
                }

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
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var placeLine: String {
        [area.trimmed(), sequence.trimmed()].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// One click to the plan, beside the ⋯ menu.
    private func lessonPlanButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label("Lesson Plan", systemImage: "doc.richtext")
                .frame(height: 30)
        }
        .fixedSize()
        .keyboardShortcut("l", modifiers: .command)
        .help("Open the lesson plan in Pages (⌘L)")
        .accessibilityLabel("Lesson Plan")
        .accessibilityHint("Opens the lesson's Pages file")
    }

    @ViewBuilder
    private var title: some View {
        if let onOpenLessonPlan {
            Button(action: onOpenLessonPlan) {
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
