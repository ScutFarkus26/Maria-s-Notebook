// SchoolYearPicker.swift
// The global "viewing year" control (a compact Menu) and the non-current-year banner.
// Both read the shared `SchoolYearStore` from the dependency environment, so the whole app
// reacts to a single selection.

import SwiftUI

/// Compact menu for choosing the viewing lens: this year / this cycle / a specific year / all.
struct SchoolYearPicker: View {
    @Environment(\.dependencies) private var dependencies

    private var store: SchoolYearStore { dependencies.schoolYearStore }

    var body: some View {
        Menu {
            Button { store.selectCurrentYear() } label: {
                menuLabel("This year (\(store.current.label))", selected: store.isCurrentYearSelected)
            }
            Button { store.selectCurrentCycle() } label: {
                menuLabel("This cycle (\(store.cycleYears) years)", selected: store.isCycleSelected)
            }

            Divider()

            ForEach(store.availableYears) { year in
                Button { store.select(year) } label: {
                    menuLabel(year.label, selected: store.isSelected(year))
                }
            }

            Divider()

            Button { store.selectAllTime() } label: {
                menuLabel("All years", selected: store.isAllTimeSelected)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "calendar")
                    .font(.system(size: 13, weight: .medium))
                Text(store.menuButtonLabel)
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(store.isCurrentYearSelected ? .secondary : .primary)
        }
        .fixedSize()
        .accessibilityLabel("Viewing school year")
        .accessibilityValue(store.menuButtonLabel)
    }

    @ViewBuilder
    private func menuLabel(_ title: String, selected: Bool) -> some View {
        if selected {
            Label(title, systemImage: "checkmark")
        } else {
            Text(title)
        }
    }
}

/// Tinted banner shown whenever the lens is not the current school year, so historical or
/// all-years views are unmistakable. Tapping "Current year" returns to the default.
struct SchoolYearBanner: View {
    @Environment(\.dependencies) private var dependencies

    private var store: SchoolYearStore { dependencies.schoolYearStore }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar.badge.clock")
                .font(.footnote)
            Text(store.bannerText)
                .font(.footnote.weight(.medium))
            Spacer(minLength: 8)
            Button("Current year") { store.selectCurrentYear() }
                .font(.footnote)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }
}

/// Settings control for the configurable school-year start month/day, plus the counter epoch
/// that decides whether "days since…" numbers restart on that day. Bound directly to the shared
/// store so a change immediately re-resolves every screen's lens and the grade boundary.
struct SchoolYearStartConfig: View {
    @Bindable var store: SchoolYearStore

    /// Resolved once. This was a computed property, and `monthName(_:)` reads it
    /// per month — so drawing the picker allocated a `DateFormatter` and an ICU
    /// calendar twelve times over on every body pass.
    private static let monthSymbols: [String] = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        return formatter.monthSymbols ?? []
    }()

    private func monthName(_ month: Int) -> String {
        let symbols = Self.monthSymbols
        guard (1...symbols.count).contains(month) else { return "\(month)" }
        return symbols[month - 1]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("School year start")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Picker("Month", selection: $store.startMonth) {
                    ForEach(1...12, id: \.self) { month in
                        Text(monthName(month)).tag(month)
                    }
                }
                .labelsHidden()

                Picker("Day", selection: $store.startDay) {
                    ForEach(1...31, id: \.self) { day in
                        Text("\(day)").tag(day)
                    }
                }
                .labelsHidden()
            }

            Text(
                "The \(store.current.label) school year began \(startDateText). Changing the start "
                + "re-buckets which year past activity falls into; it never moves or deletes data."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)

            Divider()
                .padding(.vertical, 4)

            counterSection
        }
    }

    // MARK: - Counters

    /// The counter epoch control. "Days since" numbers are the ones a guide reads every
    /// morning, so they get an explicit switch rather than riding silently on the lens.
    @ViewBuilder
    private var counterSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "gauge.with.needle")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("Day counters")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Picker("Day counters count from", selection: countersResetBinding) {
                Text("Start of the school year").tag(true)
                Text("All history").tag(false)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text(counterExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)

            if store.isResettingCounters, store.counterEpoch != store.current.start {
                Button {
                    store.setCountersResetAtYearStart(true)
                } label: {
                    Label("Reset counters to \(startDateText)", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private var countersResetBinding: Binding<Bool> {
        Binding(
            get: { store.isResettingCounters },
            set: { store.setCountersResetAtYearStart($0) }
        )
    }

    private var counterExplanation: String {
        guard let epoch = store.counterEpoch else {
            return "Days since last lesson, days since last meeting, and work-aging counters "
                + "measure from the last activity, however long ago it was."
        }
        return "Days since last lesson, days since last meeting, and work-aging counters start "
            + "over on \(Self.dateText(epoch)) — anything older counts from that day, so every "
            + "counter reads 0 on the first morning of school."
    }

    private var startDateText: String { Self.dateText(store.current.start) }

    private static func dateText(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).day().year())
    }
}
