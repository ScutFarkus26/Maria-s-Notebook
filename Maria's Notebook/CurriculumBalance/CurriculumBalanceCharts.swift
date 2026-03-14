// CurriculumBalanceCharts.swift
// Chart components for Curriculum Balance Analytics.
// Uses Swift Charts framework (same pattern as Components/TodoAnalyticsView.swift).

import SwiftUI
import Charts

/// Donut chart showing subject distribution.
struct SubjectDistributionChart: View {
    let data: [SubjectDistribution]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Subject Distribution")
                .font(AppTheme.ScaledFont.calloutSemibold)

            if data.isEmpty {
                Text("No data available")
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.tertiary)
                    .frame(height: 200)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(data) { item in
                    SectorMark(
                        angle: .value("Count", item.count),
                        innerRadius: .ratio(0.5),
                        angularInset: 1.5
                    )
                    .foregroundStyle(item.color)
                    .cornerRadius(3)
                }
                .frame(height: 200)

                // Legend
                legendGrid
            }
        }
        .padding()
        .background(Color.primary.opacity(0.02))
        .cornerRadius(UIConstants.CornerRadius.large)
    }

    private var legendGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ], spacing: 6) {
            ForEach(data) { item in
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.color)
                        .frame(width: 8, height: 8)

                    Text(item.subject)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer()

                    Text("\(item.count)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

/// Stacked bar chart showing weekly trends by subject.
struct SubjectWeeklyTrendChart: View {
    let data: [SubjectWeeklyTrend]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Weekly Trends")
                .font(AppTheme.ScaledFont.calloutSemibold)

            if data.isEmpty {
                Text("No data available")
                    .font(AppTheme.ScaledFont.body)
                    .foregroundStyle(.tertiary)
                    .frame(height: 220)
                    .frame(maxWidth: .infinity)
            } else {
                Chart(data) { item in
                    BarMark(
                        x: .value("Week", item.weekStart, unit: .weekOfYear),
                        y: .value("Lessons", item.count)
                    )
                    .foregroundStyle(item.color)
                }
                .frame(height: 220)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
            }
        }
        .padding()
        .background(Color.primary.opacity(0.02))
        .cornerRadius(UIConstants.CornerRadius.large)
    }
}
