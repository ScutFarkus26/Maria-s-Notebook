import SwiftUI

/// The week strip's controls: date navigation, the legend and the actions menu,
/// on one row.
///
/// The Everything / Presentations / Work picker that used to sit here moved
/// into the actions menu. It repeated the workspace's own Presentations / Work
/// switch a few points above it, and with the legend on a row of its own the
/// header cost the strip two rows of height it needed for cards.
struct WeekPlanHeader<Actions: View>: View {
    let dateRangeLabel: String
    /// What the Show menu is set to. Anything but Everything is called out on
    /// the row, because a filter tucked inside a menu is otherwise invisible
    /// and an empty Checks section would just look like a quiet week.
    let visibleKinds: CalendarKindFilter
    let onShowEverything: () -> Void
    let onToday: () -> Void
    let onEarlier: () -> Void
    let onLater: () -> Void
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        // One row where it fits. On a phone the row is wider than the screen,
        // and a header that does not fit widens the whole Lessons & Work page
        // past it, so the legend drops to a second row that scrolls on its own.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                dateNavigation
                Spacer(minLength: 8)
                filterNote
                legend
                actions()
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    dateNavigation
                    Spacer(minLength: 0)
                    actions()
                }
                ScrollView(.horizontal) {
                    HStack(spacing: 14) {
                        filterNote
                        legend
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(.horizontal, 12)
    }

    private var dateNavigation: some View {
        HStack(spacing: 10) {
            Button("Today", action: onToday)
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button(action: onEarlier) { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
                .help("Earlier days")
                .accessibilityLabel("Earlier days")

            Text(dateRangeLabel)
                .font(.subheadline.weight(.medium))
                .monospacedDigit()
                .frame(minWidth: 110)
                .multilineTextAlignment(.center)

            Button(action: onLater) { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
                .help("Later days")
                .accessibilityLabel("Later days")
        }
    }

    @ViewBuilder
    private var filterNote: some View {
        if visibleKinds != .everything {
            Button(action: onShowEverything) {
                HStack(spacing: 4) {
                    Text("\(visibleKinds.title) only")
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .font(.caption.weight(.medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Show presentations and work")
            .accessibilityLabel("Showing \(visibleKinds.title.lowercased()) only. Show everything.")
        }
    }

    /// Icons rather than swatches: they are the same glyphs the cards and the
    /// chips draw, so the legend can be checked against a card at a glance.
    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(
                systemImage: "exclamationmark.triangle.fill",
                color: AppColors.attention,
                label: "Twice in one half"
            )
            legendItem(systemImage: "person.slash", color: .red, label: "Absent")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize()
    }

    private func legendItem(systemImage: String, color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage)
                .foregroundStyle(color)
                .accessibilityHidden(true)
            Text(label)
        }
        .accessibilityElement(children: .combine)
    }
}
