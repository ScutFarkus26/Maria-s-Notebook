// TodoEditSheet+TimeTracking.swift
// Time estimate and actual time tracking sections.

import SwiftUI

extension TodoEditSheet {
    // MARK: - Time Estimate Section

    @ViewBuilder
    var timeEstimateSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Time Tracking")
                .font(AppTheme.ScaledFont.captionSemibold)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)

            VStack(spacing: 16) {
                estimatedTimeCard
                actualTimeCard
                varianceDisplay
            }
        }
    }

    private var estimatedTimeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimated Time")
                .font(AppTheme.ScaledFont.bodySemibold)
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                hoursPicker(selection: $estimatedHours)
                minutesPicker(selection: $estimatedMinutes)
                Spacer()
                if estimatedHours > 0 || estimatedMinutes > 0 {
                    clearButton { estimatedHours = 0; estimatedMinutes = 0 }
                }
            }
        }
        .padding(12)
        .background(Color.blue.opacity(UIConstants.OpacityConstants.subtle))
        .cornerRadius(10)
    }

    private var actualTimeCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actual Time")
                .font(AppTheme.ScaledFont.bodySemibold)
                .foregroundStyle(.primary)

            HStack(spacing: 12) {
                hoursPicker(selection: $actualHours)
                minutesPicker(selection: $actualMinutes)
                Spacer()
                if actualHours > 0 || actualMinutes > 0 {
                    clearButton { actualHours = 0; actualMinutes = 0 }
                }
            }
        }
        .padding(12)
        .background(Color.green.opacity(UIConstants.OpacityConstants.subtle))
        .cornerRadius(10)
    }

    private func hoursPicker(selection: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            #if os(macOS)
            Picker("", selection: selection) {
                ForEach(0..<24) { hour in
                    Text("\(hour)").tag(hour)
                }
            }
            .frame(width: 60)
            #else
            Picker("Hours", selection: selection) {
                ForEach(0..<24) { hour in
                    Text("\(hour) hr").tag(hour)
                }
            }
            .pickerStyle(.menu)
            #endif

            Text("hours")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func minutesPicker(selection: Binding<Int>) -> some View {
        HStack(spacing: 8) {
            #if os(macOS)
            Picker("", selection: selection) {
                ForEach([0, 15, 30, 45], id: \.self) { minute in
                    Text("\(minute)").tag(minute)
                }
            }
            .frame(width: 60)
            #else
            Picker("Minutes", selection: selection) {
                ForEach([0, 15, 30, 45], id: \.self) { minute in
                    Text("\(minute) min").tag(minute)
                }
            }
            .pickerStyle(.menu)
            #endif

            Text("min")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func clearButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var varianceDisplay: some View {
        if estimatedHours > 0 || estimatedMinutes > 0 || actualHours > 0 || actualMinutes > 0 {
            let estimatedTotal: Int = estimatedHours * 60 + estimatedMinutes
            let actualTotal: Int = actualHours * 60 + actualMinutes
            let variance: Int = actualTotal - estimatedTotal
            let varianceIcon: String = variance > 0
                ? "exclamationmark.triangle.fill"
                : variance < 0 ? "checkmark.circle.fill" : "equal.circle.fill"

            HStack(spacing: 8) {
                Image(systemName: varianceIcon)
                    .foregroundStyle(variance > 0 ? .orange : variance < 0 ? .green : .blue)

                if variance == 0 && actualTotal > 0 {
                    Text("On track")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if variance > 0 {
                    Text("Over by \(formatMinutes(variance))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if variance < 0 {
                    Text("Under by \(formatMinutes(abs(variance)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.horizontal, 4)
        }
    }

    func formatMinutes(_ minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60

        if hours > 0 && mins > 0 {
            return "\(hours)h \(mins)m"
        } else if hours > 0 {
            return "\(hours)h"
        } else {
            return "\(mins)m"
        }
    }
}
