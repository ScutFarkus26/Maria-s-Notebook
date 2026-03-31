import SwiftUI
import CoreData
import OSLog

/// Sheet showing tardy counts per student over a selected date range.
struct AttendanceTardyReport: View {
    private static let logger = Logger.attendance
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CDStudent.lastName, ascending: true)])
    private var allStudentsRaw: FetchedResults<CDStudent>
    private var students: [CDStudent] { Array(allStudentsRaw).uniqueByID.filter(\.isEnrolled) }

    // Default range: last 30 days
    @State private var startDate: Date = AppCalendar.startOfDay(
        Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    )
    @State private var endDate: Date = AppCalendar.startOfDay(Date())

    private var rows: [TardyRow] {
        guard startDate <= endDate else { return [] }
        let start = AppCalendar.startOfDay(startDate)
        let end = AppCalendar.startOfDay(endDate)

        // Fetch all records in the range, then filter for tardy in memory
        let fetchRequest = NSFetchRequest<CDAttendanceRecord>(entityName: "AttendanceRecord")
        fetchRequest.predicate = NSPredicate(format: "date >= %@ AND date <= %@", start as NSDate, end as NSDate)
        let records = safeFetch(fetchRequest, context: "AttendanceTardyReport.rows")

        // Count tardies per studentID
        var countsByID: [String: Int] = [:]
        for record in records where record.status == .tardy {
            countsByID[record.studentID, default: 0] += 1
        }

        // Map to student names, include only students with at least 1 tardy
        let rows: [TardyRow] = students.compactMap { student in
            let key = student.cloudKitKey
            guard let count = countsByID[key], count > 0 else { return nil }
            return TardyRow(student: student, tardyCount: count)
        }

        return rows.sorted { $0.tardyCount > $1.tardyCount }
    }

    private var totalTardies: Int {
        rows.reduce(0) { $0 + $1.tardyCount }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Date range pickers
                dateRangeSection
                    .padding(.horizontal, AppTheme.Spacing.lg)
                    .padding(.vertical, AppTheme.Spacing.md)

                Divider()

                // Summary chip
                summaryBar

                Divider()

                // Results list
                if rows.isEmpty {
                    emptyState
                } else {
                    resultsList
                }
            }
            .navigationTitle("Tardy Report")
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

    private var summaryBar: some View {
        HStack(spacing: AppTheme.Spacing.lg) {
            summaryChip(
                value: rows.count,
                label: rows.count == 1 ? "Student" : "Students",
                color: .orange
            )
            summaryChip(
                value: totalTardies,
                label: totalTardies == 1 ? "Tardy" : "Total Tardies",
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

    private var resultsList: some View {
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
                    Text("\(row.tardyCount)")
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .foregroundStyle(AppColors.warning)
                        .frame(minWidth: 32, alignment: .trailing)
                    Text(row.tardyCount == 1 ? "tardy" : "tardies")
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
            "No Tardies",
            systemImage: "checkmark.seal",
            description: Text("No tardies recorded in the selected range.")
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
}

// MARK: - Supporting Types

private struct TardyRow: Identifiable {
    let id: UUID = UUID()
    let student: Student
    let tardyCount: Int
}

#Preview {
    AttendanceTardyReport()
        .previewEnvironment()
}
