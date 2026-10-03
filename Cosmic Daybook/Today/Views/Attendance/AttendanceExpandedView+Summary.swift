// AttendanceExpandedView+Summary.swift
// The iPhone's strip of the day's counts. (The Mac and iPad have the band.)

import SwiftUI

extension AttendanceExpandedView {

    var isCompact: Bool {
#if os(iOS)
        hSizeClass == .compact
#else
        false
#endif
    }

    // MARK: - Attendance Summary Strip (iPhone)

    @ViewBuilder
    var attendanceSummaryStrip: some View {
#if os(iOS)
        if isCompact {
            // The chips step aside when Close Arrival needs the room: the
            // tiles say the same.
            ViewThatFits(in: .horizontal) {
                summaryRow(showsChips: true)
                summaryRow(showsChips: false)
            }
            .padding(.horizontal, AppTheme.Spacing.compact)
            .padding(.bottom, AppTheme.Spacing.small)
            .animation(.smooth(duration: 0.3), value: finishedLine)
            .animation(.smooth(duration: 0.3), value: welcomeLine)
        }
#endif
    }

    private func summaryRow(showsChips: Bool) -> some View {
        HStack(spacing: 10) {
            if let finishedLine {
                Label(finishedLine, systemImage: "sparkles")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .lineLimit(1)
                    .transition(.opacity)
            } else if let welcomeLine {
                Label(welcomeLine, systemImage: "hand.wave.fill")
                    .font(AppTheme.ScaledFont.captionSemibold)
                    .lineLimit(1)
                    .transition(.opacity)
            } else {
                // Primary: In Class count
                HStack(spacing: 6) {
                    Text("In Class")
                        .font(AppTheme.ScaledFont.captionSemibold)
                        .foregroundStyle(.secondary)
                    Text("\(viewModel.inClassCount)")
                        .font(AppTheme.ScaledFont.calloutSemibold)
                        .monospacedDigit()
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .capsuleFill(Color.accentColor.opacity(UIConstants.OpacityConstants.medium))
                }
                .fixedSize()

                if showsChips {
                    statChips
                }
            }

            Spacer(minLength: 0)

            arrivalControl
        }
    }

    @ViewBuilder
    private var statChips: some View {
        if viewModel.countTardy > 0 {
            tappableStatChip(title: "Tardy", count: viewModel.countTardy, color: .blue, status: .tardy)
        }
        if viewModel.countAbsent > 0 {
            tappableStatChip(title: "Absent", count: viewModel.countAbsent, color: .red, status: .absent)
        }
        if viewModel.countLeftEarly > 0 {
            tappableStatChip(
                title: "Left Early", count: viewModel.countLeftEarly,
                color: .purple, status: .leftEarly
            )
        }
    }

    private func tappableStatChip(title: String, count: Int, color: Color, status: AttendanceStatus) -> some View {
        Button {
            activeChipPopover = activeChipPopover == status ? nil : status
        } label: {
            HStack(spacing: 4) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text("\(title) \(count)")
                    .font(AppTheme.ScaledFont.captionSmallSemibold)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().strokeBorder(color.opacity(0.20), lineWidth: 1))
            .fixedSize()
        }
        .buttonStyle(.plain)
        .popover(isPresented: Binding(
            get: { activeChipPopover == status },
            set: { if !$0 { activeChipPopover = nil } }
        )) {
            chipPopoverContent(title: title, color: color, status: status)
        }
    }

    private func chipPopoverContent(title: String, color: Color, status: AttendanceStatus) -> some View {
        let studentNames = names(for: status)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title)
                    .font(AppTheme.ScaledFont.calloutSemibold)
            }
            .padding(.bottom, 2)

            if studentNames.isEmpty {
                Text("None")
                    .font(AppTheme.ScaledFont.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(studentNames, id: \.self) { name in
                    Text(name)
                        .font(AppTheme.ScaledFont.callout)
                }
            }
        }
        .padding()
        .frame(minWidth: 160, alignment: .leading)
        .presentationCompactAdaptation(.popover)
    }
}
