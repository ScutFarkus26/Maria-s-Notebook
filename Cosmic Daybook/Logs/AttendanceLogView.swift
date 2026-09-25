import SwiftUI
import CoreData

struct AttendanceLogView: View {
    @Environment(\.managedObjectContext) var viewContext
    @Environment(\.dependencies) var dependencies
    @Environment(\.calendar) private var calendar

    // Test student filtering
    @TestStudentVisibility private var testStudents

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDAttendanceRecord.date, ascending: false)]
    )
    private var allRecords: FetchedResults<CDAttendanceRecord>

    // Filter state
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var selectedStatuses: Set<AttendanceStatus> = []
    @State private var selectedDateRange: DateRangeFilter = .thisMonth
    @State private var customStartDate: Date = AppCalendar.shared.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEndDate: Date = Date()
    @State private var searchText: String = ""

    // Date range filter options
    enum DateRangeFilter: String, CaseIterable, Identifiable {
        case thisWeek = "This Week"
        case thisMonth = "This Month"
        case lastMonth = "Last Month"
        case custom = "Custom"
        case allTime = "All Time"

        var id: String { rawValue }
    }

    // Date range bounds
    private var dateRangeBounds: (start: Date, end: Date)? {
        AttendanceLogFilter.bounds(
            for: selectedDateRange,
            customStart: customStartDate,
            customEnd: customEndDate,
            calendar: calendar,
            now: Date()
        )
    }

    // Summary stats for filtered records
    struct AttendanceSummary {
        var present = 0
        var absent = 0
        var tardy = 0
        var leftEarly = 0
        var total: Int
    }

    // Available statuses (exclude unmarked)
    var availableStatuses: [AttendanceStatus] {
        AttendanceStatus.allCases.filter { $0 != .unmarked }
    }

    // MARK: - Filter Bar

    private func filterBar(students: [CDStudent]) -> some View {
        HStack(spacing: 12) {
            MultiSelectFilterMenu(
                items: students,
                selection: $selectedStudentIDs,
                id: { $0.id },
                label: { $0.shortName },
                summary: FilterSelectionSummary(allLabel: "All Students"),
                systemImage: "person.3",
                minHeight: 44
            )

            MultiSelectFilterMenu(
                items: availableStatuses,
                selection: $selectedStatuses,
                label: { $0.displayName },
                summary: FilterSelectionSummary(allLabel: "All Statuses"),
                systemImage: "checkmark.circle",
                minHeight: 44
            )

            SingleSelectFilterMenu(
                items: DateRangeFilter.allCases,
                selection: $selectedDateRange,
                label: { $0.rawValue },
                systemImage: "calendar",
                minHeight: 44
            )

            Spacer()
        }
        .padding(.horizontal, 12)
    }

    // Custom date range picker (shown when custom is selected)
    @ViewBuilder
    private var customDateRangePicker: some View {
        if selectedDateRange == .custom {
            HStack(spacing: 16) {
                HStack(spacing: 8) {
                    Text("From:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: $customStartDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                HStack(spacing: 8) {
                    Text("To:")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    DatePicker("", selection: $customEndDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
        }
    }

    // MARK: - Body

    var body: some View {
        // Read once per render: the timeframe's bounds, the roster, and the
        // filtered records the summary, the grouping and the rows all use.
        let bounds = dateRangeBounds
        let students = AttendanceLogFilter.students(
            from: dependencies.roster.all, bounds: bounds,
            show: testStudents.show, namesRaw: testStudents.namesRaw
        )
        let studentsByID = AttendanceLogFilter.studentsByID(students)
        let records = AttendanceLogFilter.records(
            allRecords,
            matching: AttendanceLogFilter.Criteria(
                bounds: bounds, studentIDs: selectedStudentIDs,
                statuses: selectedStatuses, searchText: searchText
            ),
            studentsByID: studentsByID
        )
        VStack(spacing: 0) {
            filterBar(students: students)
                .padding(.vertical, 8)

            customDateRangePicker

            summaryStatsView(AttendanceLogFilter.summary(of: records))

            Divider()

            if records.isEmpty {
                ContentUnavailableView(
                    "No Attendance Records",
                    systemImage: "calendar.badge.clock",
                    description: Text("Attendance records will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(
                            AttendanceLogFilter.groupedByDay(records, studentsByID: studentsByID, calendar: calendar),
                            id: \.day
                        ) { entry in
                            Section {
                                ForEach(entry.items) { record in
                                    attendanceRow(for: record, studentsByID: studentsByID)
                                }
                            } header: {
                                Text(DateFormatters.mediumDate.string(from: entry.day))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 12)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .searchable(text: $searchText)
        .onAppear { applyDateRangePredicate() }
        .onChange(of: selectedDateRange) { _, _ in applyDateRangePredicate() }
        .onChange(of: customStartDate) { _, _ in applyDateRangePredicate() }
        .onChange(of: customEndDate) { _, _ in applyDateRangePredicate() }
    }

    // MARK: - Fetch Predicate

    /// Narrows the attendance fetch to the selected date range so the store returns
    /// only the visible window (index-backed by the AttendanceRecord `byDate` index)
    /// instead of loading every record ever created. A nil range (All Time) clears it.
    ///
    /// Only an optimisation: SwiftUI restores the declared, unfiltered request
    /// whenever the parent re-creates this view (checked on the iOS 27 simulator),
    /// and `AttendanceLogFilter.records` applies the same window in memory, so the
    /// rows shown never depend on it. The reset is also why `init` does not narrow
    /// the first fetch: a request built there would be restored over a timeframe
    /// chosen later and hide that timeframe's rows.
    private func applyDateRangePredicate() {
        allRecords.nsPredicate = AttendanceLogFilter.fetchPredicate(for: dateRangeBounds)
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct AttendanceLogViewPreview: View {
    var body: some View {
        AttendanceLogView()
            .previewEnvironment()
    }
}

#Preview {
    AttendanceLogViewPreview()
}
