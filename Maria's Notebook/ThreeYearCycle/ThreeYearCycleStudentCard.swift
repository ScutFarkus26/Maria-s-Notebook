// ThreeYearCycleStudentCard.swift
// Per-student card showing cycle year, coverage, and pace indicator.

import SwiftUI

struct ThreeYearCycleStudentCard: View {
    let card: CycleStudentCard

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header: name + badges
            headerRow

            // Overall progress bar
            progressBar

            // Top subject mini-bars
            if !card.subjectCoverage.isEmpty {
                subjectBars
            }
        }
        .cardStyle()
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 10) {
            // Initials circle
            Text(card.initials)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(
                    AppColors.color(forLevel: card.level).gradient,
                    in: Circle()
                )

            // Name + date started
            VStack(alignment: .leading, spacing: 2) {
                Text("\(card.firstName) \(card.lastName)")
                    .font(.subheadline)
                    .fontWeight(.medium)

                HStack(spacing: 6) {
                    // Level badge
                    Text(card.level.rawValue)
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let dateStarted = card.dateStarted {
                        Text("·")
                            .font(.caption2)
                            .foregroundStyle(.quaternary)
                        Text("Started \(dateStarted, format: .dateTime.month(.abbreviated).year())")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Year badge
            yearBadge

            // Pace badge
            paceBadge
        }
    }

    private var yearBadge: some View {
        Text(card.cycleYear.shortName)
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(card.cycleYear.color.gradient)
            )
    }

    private var paceBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: card.paceIndicator.icon)
                .font(.system(size: 9))
            Text(card.paceIndicator.displayName)
                .font(.system(size: 9))
                .fontWeight(.medium)
        }
        .foregroundStyle(card.paceIndicator.color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule(style: .continuous)
                .fill(card.paceIndicator.color.opacity(UIConstants.OpacityConstants.light))
        )
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        VStack(spacing: 4) {
            HStack {
                Text("\(card.totalLessonsPresented)/\(card.totalLessonsAvailable) lessons")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(card.coveragePercentage * 100))%")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(card.paceIndicator.color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.secondary.opacity(UIConstants.OpacityConstants.light))

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(card.paceIndicator.color.gradient)
                        .frame(width: max(0, geo.size.width * card.coveragePercentage))
                }
            }
            .frame(height: 6)
        }
    }

    // MARK: - Subject Bars

    private var subjectBars: some View {
        let topSubjects = card.subjectCoverage
            .sorted { $0.percentage < $1.percentage }
            .prefix(3)

        return VStack(spacing: 4) {
            ForEach(Array(topSubjects)) { subject in
                HStack(spacing: 6) {
                    Circle()
                        .fill(subject.color)
                        .frame(width: 6, height: 6)

                    Text(subject.subject)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .frame(width: 60, alignment: .leading)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(subject.color.opacity(UIConstants.OpacityConstants.light))

                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(subject.color)
                                .frame(width: max(0, geo.size.width * subject.percentage))
                        }
                    }
                    .frame(height: 4)

                    Text("\(subject.presented)/\(subject.total)")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .frame(width: 30, alignment: .trailing)
                }
            }
        }
    }
}
