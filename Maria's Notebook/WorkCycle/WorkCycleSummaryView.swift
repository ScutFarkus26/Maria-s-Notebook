// WorkCycleSummaryView.swift
// Post-cycle summary showing duration, student coverage, and concentration/social breakdowns.

import SwiftUI

struct WorkCycleSummaryView: View {
    let summary: CycleSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Duration header
                    durationHeader
                        .padding(.top, 16)

                    // Stats row
                    statsRow
                        .padding(.horizontal)

                    // Concentration breakdown
                    if !summary.concentrationBreakdown.isEmpty {
                        concentrationSection
                            .padding(.horizontal)
                    }

                    // Social mode breakdown
                    if !summary.socialModeBreakdown.isEmpty {
                        socialModeSection
                            .padding(.horizontal)
                    }
                }
                .padding(.bottom, 24)
            }
            .navigationTitle("Cycle Summary")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.bold)
                }
            }
        }
    }

    // MARK: - Duration Header

    private var durationHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: SFSymbol.Action.checkmarkCircleFill)
                .font(.system(size: 40))
                .foregroundStyle(AppColors.success)

            Text("Work Cycle Complete")
                .font(.title3)
                .fontWeight(.semibold)

            Text(formattedDuration)
                .font(.system(size: 32, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var formattedDuration: String {
        let total = Int(summary.duration)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes) minutes"
    }

    // MARK: - Stats Row

    private var statsRow: some View {
        HStack(spacing: 12) {
            statCard(value: summary.studentsTracked, label: "Students", icon: "person.2", color: .blue)
            statCard(value: summary.totalEntries, label: "Entries", icon: "list.bullet", color: .purple)
        }
    }

    private func statCard(value: Int, label: String, icon: String, color: Color) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
            Text("\(value)")
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .cardStyle()
    }

    // MARK: - Concentration Breakdown

    private var concentrationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Concentration")
                .font(.subheadline)
                .fontWeight(.semibold)

            let total = summary.concentrationBreakdown.values.reduce(0, +)

            VStack(spacing: 6) {
                ForEach(ConcentrationLevel.allCases) { level in
                    if let count = summary.concentrationBreakdown[level], count > 0 {
                        breakdownRow(
                            label: level.displayName,
                            icon: level.icon,
                            count: count,
                            total: total,
                            color: level.color
                        )
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Social Mode Breakdown

    private var socialModeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Social Mode")
                .font(.subheadline)
                .fontWeight(.semibold)

            let total = summary.socialModeBreakdown.values.reduce(0, +)

            VStack(spacing: 6) {
                ForEach(SocialMode.allCases) { mode in
                    if let count = summary.socialModeBreakdown[mode], count > 0 {
                        breakdownRow(
                            label: mode.displayName,
                            icon: mode.icon,
                            count: count,
                            total: total,
                            color: .blue
                        )
                    }
                }
            }
        }
        .cardStyle()
    }

    // MARK: - Breakdown Row

    private func breakdownRow(label: String, icon: String, count: Int, total: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 20)

            Text(label)
                .font(.caption)
                .frame(width: 80, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color.opacity(UIConstants.OpacityConstants.light))

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color.gradient)
                        .frame(width: max(0, geo.size.width * (total > 0 ? Double(count) / Double(total) : 0)))
                }
            }
            .frame(height: 6)

            Text("\(count)")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
    }
}
