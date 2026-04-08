// ThreeYearCycleDetailView.swift
// Drill-down view showing full subject breakdown for a student's three-year cycle.

import SwiftUI

struct ThreeYearCycleDetailView: View {
    let card: CycleStudentCard

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Header
                headerSection
                    .padding(.horizontal)
                    .padding(.top, 8)

                // Overall progress
                overallProgressSection
                    .padding(.horizontal)

                Divider()
                    .padding(.horizontal)

                // Full subject breakdown
                subjectBreakdownSection
                    .padding(.horizontal)

                // Recommendations
                if !needsAttentionSubjects.isEmpty {
                    recommendationsSection
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, 24)
        }
        .navigationTitle(card.displayName)
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 14) {
            Text(card.initials)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    AppColors.color(forLevel: card.level).gradient,
                    in: Circle()
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("\(card.firstName) \(card.lastName)")
                    .font(.title3)
                    .fontWeight(.bold)

                HStack(spacing: 8) {
                    Text(card.level.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(card.cycleYear.displayName)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(card.cycleYear.color)

                    if let started = card.dateStarted {
                        Text("Since \(started, format: .dateTime.month(.abbreviated).year())")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            Spacer()

            // Pace badge
            VStack(spacing: 4) {
                Image(systemName: card.paceIndicator.icon)
                    .font(.title2)
                    .foregroundStyle(card.paceIndicator.color)

                Text(card.paceIndicator.displayName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(card.paceIndicator.color)
            }
        }
    }

    // MARK: - Overall Progress

    private var overallProgressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Overall Coverage")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack {
                Text("\(card.totalLessonsPresented)")
                    .font(.title)
                    .fontWeight(.bold)

                Text("of \(card.totalLessonsAvailable) lessons presented")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(Int(card.coveragePercentage * 100))%")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(card.paceIndicator.color)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.secondary.opacity(UIConstants.OpacityConstants.light))

                    // Expected progress marker
                    if card.cycleYear != .unknown {
                        let expected = Double(card.cycleYear.rawValue) / 3.0
                        Rectangle()
                            .fill(Color.secondary.opacity(0.3))
                            .frame(width: 2)
                            .offset(x: geo.size.width * expected)
                    }

                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(card.paceIndicator.color.gradient)
                        .frame(width: max(0, geo.size.width * card.coveragePercentage))
                }
            }
            .frame(height: 8)

            if card.cycleYear != .unknown {
                let expected = Int(Double(card.cycleYear.rawValue) / 3.0 * 100)
                Text("Expected at \(card.cycleYear.displayName): ~\(expected)%")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .cardStyle()
    }

    // MARK: - Subject Breakdown

    private var sortedSubjects: [SubjectCoverage] {
        card.subjectCoverage.sorted { $0.percentage < $1.percentage }
    }

    private var subjectBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Subject Breakdown")
                .font(.subheadline)
                .fontWeight(.semibold)

            LazyVStack(spacing: 8) {
                ForEach(sortedSubjects) { subject in
                    subjectRow(subject)
                }
            }
        }
    }

    private func subjectRow(_ subject: SubjectCoverage) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(subject.color)
                    .frame(width: 8, height: 8)

                Text(subject.subject)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Text("\(subject.presented)/\(subject.total)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(subject.percentage < 0.3 ? AppColors.warning : .primary)

                Text("\(Int(subject.percentage * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 32, alignment: .trailing)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(subject.color.opacity(UIConstants.OpacityConstants.light))

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(subject.color.gradient)
                        .frame(width: max(0, geo.size.width * subject.percentage))
                }
            }
            .frame(height: 6)
        }
        .cardStyle()
    }

    // MARK: - Recommendations

    private var needsAttentionSubjects: [SubjectCoverage] {
        guard card.cycleYear != .unknown else { return [] }
        let expectedPercentage = Double(card.cycleYear.rawValue) / 3.0
        let threshold = expectedPercentage * 0.5
        return card.subjectCoverage.filter { $0.percentage < threshold }
            .sorted { $0.percentage < $1.percentage }
    }

    private var recommendationsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AppColors.warning)
                Text("Subjects Needing Attention")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            FlowLayout(spacing: 6) {
                ForEach(needsAttentionSubjects) { subject in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(subject.color)
                            .frame(width: 6, height: 6)
                        Text(subject.subject)
                            .font(.caption)
                            .fontWeight(.medium)
                        Text("\(Int(subject.percentage * 100))%")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(AppColors.warning.opacity(UIConstants.OpacityConstants.light))
                    )
                }
            }
        }
        .cardStyle()
    }
}
