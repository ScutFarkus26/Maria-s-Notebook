// AttendanceInsightsSidebar.swift
// Right-column container that hosts the three insight cards plus a timeframe picker.

import SwiftUI
import CoreData

/// Time window options for the insights sidebar.
enum AttendanceInsightsTimeframe: String, CaseIterable, Identifiable, Sendable {
    case last7
    case last30
    case last90
    case schoolYear

    var id: String { rawValue }

    var label: String {
        switch self {
        case .last7: return "Last 7 days"
        case .last30: return "Last 30 days"
        case .last90: return "Last 90 days"
        case .schoolYear: return "This school year"
        }
    }

    var shortLabel: String {
        switch self {
        case .last7: return "7d"
        case .last30: return "30d"
        case .last90: return "90d"
        case .schoolYear: return "Year"
        }
    }

    /// Range ending at `referenceDate` (inclusive) for this timeframe.
    func range(endingAt referenceDate: Date) -> ClosedRange<Date> {
        let end = AppCalendar.startOfDay(referenceDate)
        switch self {
        case .last7, .last30, .last90:
            let start = AppCalendar.addingDays(-(fixedDays - 1), to: end)
            return start...end
        case .schoolYear:
            let start = AppCalendar.startOfDay(FloridaGradeCalculator.schoolYearStart(for: referenceDate))
            return start...end
        }
    }

    /// Comparison range used to render trend deltas. Fixed-window timeframes step back by their
    /// own length; the school year compares to the same period in the prior school year.
    func priorRange(for range: ClosedRange<Date>) -> ClosedRange<Date> {
        switch self {
        case .last7, .last30, .last90:
            let priorEnd = AppCalendar.addingDays(-fixedDays, to: range.lowerBound)
            let priorStart = AppCalendar.addingDays(-(fixedDays - 1), to: priorEnd)
            return priorStart...priorEnd
        case .schoolYear:
            let cal = Calendar.current
            let priorStart = cal.date(byAdding: .year, value: -1, to: range.lowerBound) ?? range.lowerBound
            let priorEnd = cal.date(byAdding: .year, value: -1, to: range.upperBound) ?? range.upperBound
            return AppCalendar.startOfDay(priorStart)...AppCalendar.startOfDay(priorEnd)
        }
    }

    private var fixedDays: Int {
        switch self {
        case .last7: return 7
        case .last30: return 30
        case .last90: return 90
        case .schoolYear: return 0
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
            .frame(width: 220)
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
        let range = timeframe.range(endingAt: referenceDate)
        let priorRange = timeframe.priorRange(for: range)
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
}
