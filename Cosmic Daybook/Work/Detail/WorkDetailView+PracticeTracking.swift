import SwiftUI
import CoreData
import Foundation

// MARK: - Practice Tracking

extension WorkDetailView {

    // MARK: - Practice Overview Helpers

    func calculatePracticeStats() -> PracticeStats {
        PracticeStatsCalculator.calculate(from: practiceSessions)
    }

    /// One fetch of the children and one of the work items this work's practice
    /// history names, for the whole section. Every card used to carry its own
    /// unpredicated `@FetchRequest` of both whole tables — a live
    /// fetched-results controller per card, per table — and then filter them
    /// down to the two or three rows it actually draws.
    func loadPracticeParticipants() {
        let sessions = practiceSessions
        let studentIDs = Set(sessions.flatMap(\.studentIDsArray).compactMap(UUID.init(uuidString:)))
        let workIDs = Set(sessions.flatMap(\.workItemIDsArray).compactMap(UUID.init(uuidString:)))

        if studentIDs.isEmpty {
            practiceStudents = []
        } else {
            let request = CDFetchRequest(CDStudent.self)
            request.predicate = NSPredicate(format: "id IN %@", Array(studentIDs))
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CDStudent.firstName, ascending: true)]
            // DEDUPLICATION: CloudKit sync can leave two rows carrying one id.
            practiceStudents = modelContext.safeFetch(request).uniqueByID
        }

        if workIDs.isEmpty {
            practiceWorkItems = []
        } else {
            let request = CDFetchRequest(CDWorkModel.self)
            request.predicate = NSPredicate(format: "id IN %@", Array(workIDs))
            request.sortDescriptors = [NSSortDescriptor(keyPath: \CDWorkModel.createdAt, ascending: false)]
            practiceWorkItems = modelContext.safeFetch(request).uniqueByID
        }
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

                // Quality metrics row
                if stats.avgQuality != nil || stats.avgIndependence != nil {
                    HStack(spacing: 16) {
                        if let avgQuality = stats.avgQuality {
                            QualityMetricBox(
                                level: avgQuality,
                                label: "Avg Quality",
                                icon: "star.fill",
                                color: .blue
                            )
                        }

                        if let avgIndependence = stats.avgIndependence {
                            QualityMetricBox(
                                level: avgIndependence,
                                label: "Avg Independence",
                                icon: "figure.walk",
                                color: .green
                            )
                        }
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
        if !practiceSessions.isEmpty {
            DetailSectionCard(
                title: "Practice History",
                icon: "person.2.fill",
                accentColor: .blue
            ) {
                VStack(spacing: 12) {
                    ForEach(practiceSessions) { session in
                        PracticeSessionCard(
                            session: session,
                            displayMode: .standard,
                            allStudents: practiceStudents,
                            allWork: practiceWorkItems
                        ) {
                            selectedPracticeSession = session
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    func practiceSessionDetailSheet(session: CDPracticeSession) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.large) {
                    PracticeSessionCard(
                        session: session,
                        displayMode: .expanded,
                        allStudents: practiceStudents,
                        allWork: practiceWorkItems
                    )
                }
                .padding(AppTheme.Spacing.large)
            }
            .navigationTitle("Practice Session")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        selectedPracticeSession = nil
                    }
                }
            }
        }
    }
}
