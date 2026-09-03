import SwiftUI
import CoreData
import OSLog

/// The per-status wording and colors that distinguish the absence report from
/// the tardy report. Everything else about the two sheets is identical.
struct AttendanceStatusReportConfig {
    /// The attendance status whose records are counted.
    let status: AttendanceStatus
    /// Navigation title of the sheet.
    let title: String
    /// Color of the "Students" summary chip value.
    let studentsChipColor: Color
    /// Color of the per-student count in the results list.
    let countColor: Color
    /// Summary-chip label when the total is exactly one (e.g. "Absence").
    let totalSingularLabel: String
    /// Summary-chip label otherwise (e.g. "Total Absences").
    let totalPluralLabel: String
    /// Lower-case row unit when the count is exactly one (e.g. "absence").
    let rowSingularLabel: String
    /// Lower-case row unit otherwise (e.g. "absences").
    let rowPluralLabel: String
    /// Empty-state title (e.g. "No Absences").
    let emptyTitle: String
    /// Empty-state description.
    let emptyDescription: String
    /// Context string attached to fetch-failure log lines.
    let fetchContext: String

    static let absence = AttendanceStatusReportConfig(
        status: .absent,
        title: "Absence Report",
        studentsChipColor: .red,
        countColor: AppColors.destructive,
        totalSingularLabel: "Absence",
        totalPluralLabel: "Total Absences",
        rowSingularLabel: "absence",
        rowPluralLabel: "absences",
        emptyTitle: "No Absences",
        emptyDescription: "No absences recorded in the selected range.",
        fetchContext: "AttendanceAbsenceReport.rows"
    )

    static let tardy = AttendanceStatusReportConfig(
        status: .tardy,
        title: "Tardy Report",
        studentsChipColor: .orange,
        countColor: AppColors.warning,
        totalSingularLabel: "Tardy",
        totalPluralLabel: "Total Tardies",
        rowSingularLabel: "tardy",
        rowPluralLabel: "tardies",
        emptyTitle: "No Tardies",
        emptyDescription: "No tardies recorded in the selected range.",
        fetchContext: "AttendanceTardyReport.rows"
    )
}

/// Sheet showing per-student counts of one attendance status over a selected
/// date range. `AttendanceAbsenceReport` and `AttendanceTardyReport` are thin
/// wrappers that supply the config.
struct AttendanceStatusReport: View {
    private static let logger = Logger.attendance
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dependencies) private var dependencies

    let config: AttendanceStatusReportConfig

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudent.lastName, ascending: true)])
    private var allStudentsRaw: FetchedResults<CDStudent>
    // Active-in-range, not enrolled-only: former students must keep appearing in
    // reports covering the period they were part of the class.
    private var students: [CDStudent] {
        let start = AppCalendar.startOfDay(startDate)
        let dayAfterEnd = AppCalendar.shared.date(byAdding: .day, value: 1, to: AppCalendar.startOfDay(endDate))
            ?? AppCalendar.startOfDay(endDate)
        return Array(allStudentsRaw).uniqueByID.filterActive(in: DateRange(start: start, end: dayAfterEnd))
    }

    // Default range: last 30 days
    @State private var startDate: Date = AppCalendar.startOfDay(
        Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    )
    @State private var endDate: Date = AppCalendar.startOfDay(Date())

    /// Called once at the top of `body`. This was a computed property read
    /// six times per body pass (directly and via the total), each read
    /// re-running the ranged fetch, the per-day dedup, and the sort — and the
    /// body re-evaluates on every date-picker change.
    private func computeRows() -> [StatusRow] {
        guard startDate <= endDate else { return [] }
        let start = AppCalendar.startOfDay(startDate)
        let end = AppCalendar.startOfDay(endDate)

        // Fetch all records in the range, then filter for the status in memory
        let fetchRequest = NSFetchRequest<CDAttendanceRecord>(entityName: "AttendanceRecord")
        fetchRequest.predicate = NSPredicate(format: "date >= %@ AND date <= %@", start as NSDate, end as NSDate)
        let records = safeFetch(fetchRequest, context: config.fetchContext)
            .deduplicatedPerStudentDay()

        // Count matching records per studentID
        var countsByID: [String: Int] = [:]
        for record in records where record.status == config.status {
            countsByID[record.studentID, default: 0] += 1
        }

        // Map to student names, include only students with at least 1 match
        let rows: [StatusRow] = students.compactMap { student in
            let key = student.cloudKitKey
            guard let count = countsByID[key], count > 0 else { return nil }
            return StatusRow(student: student, count: count)
        }

        return rows.sorted { $0.count > $1.count }
    }

    var body: some View {
        let rows = computeRows()
        let total = rows.reduce(0) { $0 + $1.count }
        return NavigationStack {
            VStack(spacing: 0) {
                // Date range pickers
                dateRangeSection
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.md)

                Divider()

                // Summary chip
                summaryBar(rows: rows, total: total)

                Divider()

                // Results list
                if rows.isEmpty {
                    emptyState
                } else {
                    resultsList(rows)
                }
            }
            .navigationTitle(config.title)
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #else
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        #endif
    }

    // MARK: - Date Range Section

    private var dateRangeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Date Range")
                .font(.headline)

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("From")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("From", selection: $startDate, in: ...endDate, displayedComponents: .date)
                        .labelsHidden()
                }

                Image(systemName: SFSymbol.Arrow.right)
                    .foregroundStyle(.secondary)
                    .font(.caption)

                VStack(alignment: .leading, spacing: 4) {
                    Text("To")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("To", selection: $endDate, in: startDate..., displayedComponents: .date)
                        .labelsHidden()
                }

                Spacer()

                // Quick range presets
                Menu {
                    Button("Last 7 Days") { applyPreset(days: 7) }
                    Button("Last 30 Days") { applyPreset(days: 30) }
                    Button("Last 90 Days") { applyPreset(days: 90) }
                    Divider()
                    Button("This School Year") { applyCurrentSchoolYearPreset() }
                    if let range = dependencies.schoolYearStore.activeRange,
                       !dependencies.schoolYearStore.isCurrentYearSelected {
                        Button("Match viewing: \(dependencies.schoolYearStore.menuButtonLabel)") {
                            applyLensPreset(range)
                        }
                    }
                } label: {
                    Label("Preset", systemImage: "calendar.badge.clock")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    // MARK: - Summary Bar

    private func summaryBar(rows: [StatusRow], total: Int) -> some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            summaryChip(
                value: rows.count,
                label: rows.count == 1 ? "Student" : "Students",
                color: config.studentsChipColor
            )
            summaryChip(
                value: total,
                label: total == 1 ? config.totalSingularLabel : config.totalPluralLabel,
                color: .blue
            )
            Spacer()
        }
        .padding(.horizontal, AppTheme.Spacing.lg)
        .padding(.vertical, AppTheme.Spacing.md)
    }

    private func summaryChip(value: Int, label: String, color: Color) -> some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Text("\(value)")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(color)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Results List

    private func resultsList(_ rows: [StatusRow]) -> some View {
        List {
            ForEach(rows) { row in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.student.fullName)
                            .font(.body)
                        Text(row.student.level.rawValue)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(row.count)")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(config.countColor)
                        .frame(minWidth: 32, alignment: .trailing)
                    Text(row.count == 1 ? config.rowSingularLabel : config.rowPluralLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView(
            config.emptyTitle,
            systemImage: "checkmark.seal",
            description: Text(config.emptyDescription)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func safeFetch<T: NSManagedObject>(_ request: NSFetchRequest<T>, context: String = #function) -> [T] {
        do {
            return try viewContext.fetch(request)
        } catch {
            Self.logger.warning("Failed to fetch \(T.self, privacy: .public) in \(context, privacy: .public): \(error)")
            return []
        }
    }

    private func applyPreset(days: Int) {
        endDate = AppCalendar.startOfDay(Date())
        startDate = AppCalendar.startOfDay(
            Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        )
    }

    private func applyCurrentSchoolYearPreset() {
        endDate = AppCalendar.startOfDay(Date())
        startDate = AppCalendar.startOfDay(FloridaGradeCalculator.schoolYearStart())
    }

    /// Snap the report range to the globally-selected school-year lens (a specific year or cycle).
    private func applyLensPreset(_ range: DateRange) {
        startDate = AppCalendar.startOfDay(range.start)
        endDate = AppCalendar.startOfDay(AppCalendar.addingDays(-1, to: range.end))
    }
}

// MARK: - Supporting Types

private struct StatusRow: Identifiable {
    let id: UUID = UUID()
    let student: CDStudent
    let count: Int
}

#Preview("Absence") {
    AttendanceStatusReport(config: .absence)
        .previewEnvironment()
}

#Preview("Tardy") {
    AttendanceStatusReport(config: .tardy)
        .previewEnvironment()
}
