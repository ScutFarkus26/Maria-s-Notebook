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
                // Estimated Time
                VStack(alignment: .leading, spacing: 8) {
                    Text("Estimated Time")
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.primary)

                    HStack(spacing: 12) {
                        // Hours picker
                        HStack(spacing: 8) {
                            #if os(macOS)
                            Picker("", selection: $estimatedHours) {
                                ForEach(0..<24) { hour in
                                    Text("\(hour)").tag(hour)
                                }
                            }
                            .frame(width: 60)
                            #else
                            Picker("Hours", selection: $estimatedHours) {
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

                        // Minutes picker
                        HStack(spacing: 8) {
                            #if os(macOS)
                            Picker("", selection: $estimatedMinutes) {
                                ForEach([0, 15, 30, 45], id: \.self) { minute in
                                    Text("\(minute)").tag(minute)
                                }
                            }
                            .frame(width: 60)
                            #else
                            Picker("Minutes", selection: $estimatedMinutes) {
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

                        Spacer()

                        // Clear button
                        if estimatedHours > 0 || estimatedMinutes > 0 {
                            Button {
                                estimatedHours = 0
                                estimatedMinutes = 0
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
                .background(Color.blue.opacity(0.08))
                .cornerRadius(10)

                // Actual Time
                VStack(alignment: .leading, spacing: 8) {
                    Text("Actual Time")
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.primary)

                    HStack(spacing: 12) {
                        // Hours picker
                        HStack(spacing: 8) {
                            #if os(macOS)
                            Picker("", selection: $actualHours) {
                                ForEach(0..<24) { hour in
                                    Text("\(hour)").tag(hour)
                                }
                            }
                            .frame(width: 60)
                            #else
                            Picker("Hours", selection: $actualHours) {
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

                        // Minutes picker
                        HStack(spacing: 8) {
                            #if os(macOS)
                            Picker("", selection: $actualMinutes) {
                                ForEach([0, 15, 30, 45], id: \.self) { minute in
                                    Text("\(minute)").tag(minute)
                                }
                            }
                            .frame(width: 60)
                            #else
                            Picker("Minutes", selection: $actualMinutes) {
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

                        Spacer()

                        // Clear button
                        if actualHours > 0 || actualMinutes > 0 {
                            Button {
                                actualHours = 0
                                actualMinutes = 0
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
                .background(Color.green.opacity(0.08))
                .cornerRadius(10)

                // Time variance display
                if estimatedHours > 0 || estimatedMinutes > 0 || actualHours > 0 || actualMinutes > 0 {
                    let estimatedTotal = estimatedHours * 60 + estimatedMinutes
                    let actualTotal = actualHours * 60 + actualMinutes
                    let variance = actualTotal - estimatedTotal

                    HStack(spacing: 8) {
                        let varianceIcon = variance > 0
                            ? "exclamationmark.triangle.fill"
                            : variance < 0 ? "checkmark.circle.fill" : "equal.circle.fill"
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
