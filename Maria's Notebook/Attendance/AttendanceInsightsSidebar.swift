// AttendanceInsightsSidebar.swift
// Right-column container that hosts the three insight cards plus a timeframe picker.

import SwiftUI
import CoreData

/// Time window options for the insights sidebar.
enum AttendanceInsightsTimeframe: String, CaseIterable, Identifiable, Sendable {
    case last7
    case last30
    case last90

    var id: String { rawValue }

    var label: String {
        switch self {
        case .last7: return "Last 7 days"
        case .last30: return "Last 30 days"
        case .last90: return "Last 90 days"
        }
    }

    var shortLabel: String {
        switch self {
        case .last7: return "7d"
        case .last30: return "30d"
        case .last90: return "90d"
        }
    }

    var days: Int {
        switch self {
        case .last7: return 7
        case .last30: return 30
        case .last90: return 90
        }
    }
}

struct AttendanceInsightsSidebar: View {
    let students: [CDStudent]
    let referenceDate: Date
    let reloadToken: Int
    let onSelectStudent: (UUID) -> Void
    let onSelectDate: (Date) -> Void

    @Environment(\.managedObjectContext) private var viewContext
    @State private var timeframe: AttendanceInsightsTimeframe = .last30
    @State private var summary: AttendanceClassSummary = .init()
    @State private var priorSummary: AttendanceClassSummary = .init()
    @State private var watchList: [AttendanceWatchListEntry] = []
    @State private var recentActivity: [AttendanceRecentActivityEntry] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
                timeframePicker

                AttendanceClassSummaryCard(
                    summary: summary,
                    priorSummary: priorSummary,
                    timeframeLabel: timeframe.shortLabel
                )

                AttendanceWatchListCard(
                    entries: watchList,
                    timeframeLabel: timeframe.shortLabel,
                    onSelectStudent: onSelectStudent
                )

                AttendanceRecentActivityCard(
                    entries: recentActivity,
                    onSelectDate: onSelectDate
                )

                Spacer(minLength: 0)
            }
            .padding(AppTheme.Spacing.medium)
        }
        .frame(minWidth: 280, idealWidth: 300, maxWidth: 320)
        .background(Color(nsOrSystemBackground))
        .onAppear { reloadAll() }
        .onChange(of: timeframe) { _, _ in reloadAll() }
        .onChange(of: referenceDate) { _, _ in reloadAll() }
        .onChange(of: reloadToken) { _, _ in reloadAll() }
    }

    private var timeframePicker: some View {
        HStack {
            Text("Insights")
                .font(.system(.headline, design: .rounded))
            Spacer()
            Picker("Timeframe", selection: $timeframe) {
                ForEach(AttendanceInsightsTimeframe.allCases) { tf in
                    Text(tf.shortLabel).tag(tf)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 170)
        }
    }

    private var nsOrSystemBackground: Color {
        #if os(macOS)
        return Color(nsColor: .controlBackgroundColor)
        #else
        return Color(uiColor: .systemBackground)
        #endif
    }

    // MARK: Reload

    private func reloadAll() {
        let range = currentRange()
        let priorRange = priorRange(for: range)
        summary = AttendanceInsightsService.classSummary(in: range, students: students, context: viewContext)
        priorSummary = AttendanceInsightsService.classSummary(in: priorRange, students: students, context: viewContext)
        watchList = AttendanceInsightsService.watchList(in: range, students: students, context: viewContext, limit: 5)
        recentActivity = AttendanceInsightsService.recentActivity(
            endingAt: range.upperBound,
            dayCount: 5,
            students: students,
            context: viewContext
        )
    }

    private func currentRange() -> ClosedRange<Date> {
        let end = AppCalendar.startOfDay(referenceDate)
        let start = AppCalendar.addingDays(-(timeframe.days - 1), to: end)
        return start...end
    }

    private func priorRange(for range: ClosedRange<Date>) -> ClosedRange<Date> {
        let length = timeframe.days
        let priorEnd = AppCalendar.addingDays(-length, to: range.lowerBound)
        let priorStart = AppCalendar.addingDays(-(length - 1), to: priorEnd)
        return priorStart...priorEnd
    }
}
