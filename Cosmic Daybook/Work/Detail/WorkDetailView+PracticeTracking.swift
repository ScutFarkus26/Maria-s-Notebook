import SwiftUI
import CoreData
import Foundation

// MARK: - Practice Tracking

extension WorkDetailView {

    // MARK: - Practice Overview Helpers

    func calculatePracticeStats() -> PracticeStats {
        let scheduled = viewModel.work.map { WorkLogService.scheduledCheckIns(of: $0, in: modelContext) } ?? []
        return PracticeStatsCalculator.calculate(from: practiceCheckIns, scheduled: scheduled)
    }

    /// Re-reads this work's practice check-ins.
    func reloadPracticeCheckIns() {
        let mine = viewModel.practiceCheckIns(in: modelContext)
        if mine != practiceCheckIns { practiceCheckIns = mine }
    }

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    func practiceOverviewSection() -> some View {
        let stats = calculatePracticeStats()

        DetailSectionCard(
            title: "Practice Overview",
            icon: "chart.bar.fill",
            accentColor: .green
        ) {
            VStack(spacing: 16) {
                // Top row: Sessions and Time
                HStack(spacing: 16) {
                    MetricStatBox(
                        value: "\(stats.totalSessions)",
                        label: stats.totalSessions == 1 ? "Session" : "Sessions",
                        icon: "calendar",
                        color: .blue
                    )

                    if let totalTime = stats.totalDuration {
                        MetricStatBox(
                            value: totalTime,
                            label: "Practice Time",
                            icon: "clock",
                            color: .purple
                        )
                    }
                }

                // Behavior highlights
                if !stats.topBehaviors.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Recent Observations")
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(.secondary)

                        FlowLayout(spacing: 6) {
                            ForEach(stats.topBehaviors, id: \.self) { behavior in
                                BehaviorPill(behavior: behavior)
                            }
                        }
                    }
                }

                // Action items
                if stats.needsReteaching > 0 || stats.upcomingCheckIns > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Action Items")
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            if stats.needsReteaching > 0 {
                                ActionItemBox(
                                    count: stats.needsReteaching,
                                    label: "Needs Reteaching",
                                    icon: "arrow.counterclockwise",
                                    color: .orange
                                )
                            }

                            if stats.upcomingCheckIns > 0 {
                                ActionItemBox(
                                    count: stats.upcomingCheckIns,
                                    label: "Check-ins Scheduled",
                                    icon: "calendar.badge.clock",
                                    color: .blue
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    func practiceHistorySection() -> some View {
        if !practiceCheckIns.isEmpty {
            DetailSectionCard(
                title: "Practice History",
                icon: "person.2.fill",
                accentColor: .blue
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(practiceCheckIns, id: \.objectID) { checkIn in
                        practiceRow(checkIn)
                    }
                }
            }
        }
    }

    /// One practice: its day and minutes, then what its note says.
    private func practiceRow(_ checkIn: CDWorkCheckIn) -> some View {
        let notes = ((checkIn.notes as? Set<CDNote>) ?? [])
            .filter { !$0.isDeleted }
            .sorted { ($0.createdAt ?? .distantPast) < ($1.createdAt ?? .distantPast) }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(checkIn.date.map { DateFormatters.mediumDate.string(from: $0) } ?? "No date")
                    .font(AppTheme.ScaledFont.bodySemibold)
                if let minutes = checkIn.durationMinutesValue {
                    Text("\(minutes) min")
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(notes, id: \.objectID) { note in
                if !note.body.isEmpty {
                    Text(note.body)
                        .font(AppTheme.ScaledFont.caption)
                        .foregroundStyle(.secondary)
                }
                if !note.tagsArray.isEmpty {
                    FlowLayout(spacing: 6) {
                        ForEach(note.tagsArray, id: \.self) { BehaviorPill(behavior: $0) }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
