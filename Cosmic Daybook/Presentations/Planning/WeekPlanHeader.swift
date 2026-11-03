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

    /// The key to a card's name chips, drawn as small chips themselves: a
    /// ringed one for each ring color, and the grey glyph for earlier work.
    /// The colors and glyphs are the card's own, so the two always agree.
    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(label: "Two lessons in one half") {
                ringSwatch(PresentationPlannerCard.clashRing) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(PresentationPlannerCard.clashRing)
                }
            }
            legendItem(label: "Absent") {
                ringSwatch(PresentationPlannerCard.absentRing) { EmptyView() }
            }
            legendItem(label: "Work to check first") {
                Image(systemName: WorkToShowFirst.glyph)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize()
    }

    private func legendItem(label: String, @ViewBuilder mark: () -> some View) -> some View {
        HStack(spacing: 4) {
            mark()
                .accessibilityHidden(true)
            Text(label)
        }
        .accessibilityElement(children: .combine)
    }

    /// A blank name chip with the card's ring, its 1.5 pt stroke included.
    /// A fixed size, so the absent swatch, which has nothing in it, matches.
    private func ringSwatch(_ color: Color, @ViewBuilder content: () -> some View) -> some View {
        content()
            .imageScale(.small)
            .frame(width: 24, height: 14)
            .capsuleFill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
            .overlay(Capsule().stroke(color, lineWidth: 1.5))
    }
}
