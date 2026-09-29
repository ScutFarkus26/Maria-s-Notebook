import SwiftUI

/// The week strip's controls: date navigation, the kind filter with the bulk
/// actions beside it, and the legend.
struct WeekPlanHeader<Actions: View>: View {
    let dateRangeLabel: String
    @Binding var visibleKinds: CalendarKindFilter
    let onToday: () -> Void
    let onEarlier: () -> Void
    let onLater: () -> Void
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(spacing: 6) {
            // One row where it fits. On a phone the row was ~640 points wide,
            // which widened the whole Lessons & Work page past the screen, so
            // the date navigation and the filters split onto two rows there.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    dateNavigation
                    Spacer()
                    filterControls
                }

                VStack(alignment: .leading, spacing: 6) {
                    dateNavigation
                    HStack(spacing: 10) {
                        filterControls
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 12)

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    Spacer()
                    legend
                }
                ScrollView(.horizontal) {
                    legend
                }
                .scrollIndicators(.hidden)
            }
            .padding(.horizontal, 12)
        }
    }

    private var dateNavigation: some View {
        HStack(spacing: 10) {
            Button("Today", action: onToday)
                .buttonStyle(.bordered)
                .controlSize(.small)

            Button(action: onEarlier) { Image(systemName: "chevron.left") }
                .buttonStyle(.plain)
                .help("Earlier days")

            Text(dateRangeLabel)
                .font(.subheadline.weight(.medium))
                .frame(minWidth: 180)
                .multilineTextAlignment(.center)

            Button(action: onLater) { Image(systemName: "chevron.right") }
                .buttonStyle(.plain)
                .help("Later days")
        }
    }

    private var filterControls: some View {
        HStack(spacing: 10) {
            Picker("Show", selection: $visibleKinds) {
                ForEach(CalendarKindFilter.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            .fixedSize()

            actions()
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendSwatch(color: .red, label: "Absent")
            legendSwatch(color: AppColors.attention, label: "Twice in the same half")
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
    }

    private func legendSwatch(color: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Capsule()
                .stroke(color, lineWidth: 1)
                .frame(width: 18, height: 11)
            Text(label)
        }
    }
}
