import SwiftUI
import SwiftData
import OSLog

struct AttendanceLogView: View {
    private static let logger = Logger.attendance
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    // Test student filtering
    @AppStorage("General.showTestStudents") private var showTestStudents: Bool = false
    @AppStorage("General.testStudentNames") private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @Query(sort: [SortDescriptor(\AttendanceRecord.date, order: .reverse)])
    private var allRecords: [AttendanceRecord]

    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)])
    private var studentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var students: [Student] {
        TestStudentsFilter.filterVisible(studentsRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    // Filter state
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var selectedStatuses: Set<AttendanceStatus> = []
    @State private var selectedDateRange: DateRangeFilter = .allTime
    @State private var customStartDate: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
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

    // Maps for quick lookup
    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var studentsByID: [UUID: Student] {
        Dictionary(students.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // Date range bounds
    private var dateRangeBounds: (start: Date, end: Date)? {
        switch selectedDateRange {
        case .thisWeek:
            let now = Date()
            let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? now
            return (start, end)
        case .thisMonth:
            let now = Date()
            let start = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let end = calendar.date(byAdding: .month, value: 1, to: start) ?? now
            return (start, end)
        case .lastMonth:
            let now = Date()
            let thisMonthStart = calendar.dateInterval(of: .month, for: now)?.start ?? now
            let start = calendar.date(byAdding: .month, value: -1, to: thisMonthStart) ?? now
            return (start, thisMonthStart)
        case .custom:
            let start = calendar.startOfDay(for: customStartDate)
            let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: customEndDate)) ?? customEndDate
            return (start, end)
        case .allTime:
            return nil
        }
    }

    // Filtered records
    private var filteredRecords: [AttendanceRecord] {
        allRecords.filter { record in
            // Exclude unmarked records from the log
            if record.status == .unmarked { return false }

            // Date range filter
            if let bounds = dateRangeBounds {
                if record.date < bounds.start || record.date >= bounds.end { return false }
            }

            // Student filter
            if !selectedStudentIDs.isEmpty {
                guard let studentID = record.studentIDUUID else { return false }
                if !selectedStudentIDs.contains(studentID) { return false }
            }

            // Status filter
            if !selectedStatuses.isEmpty {
                if !selectedStatuses.contains(record.status) { return false }
            }

            // Search filter (search student name)
            if !searchText.isEmpty {
                guard let studentID = record.studentIDUUID,
                      let student = studentsByID[studentID] else { return false }
                let name = displayName(for: student).lowercased()
                let query = searchText.lowercased()
                if !name.contains(query) { return false }
            }

            return true
        }
    }

    // Summary stats for filtered records
    private var summaryStats: (present: Int, absent: Int, tardy: Int, leftEarly: Int, total: Int) {
        var present = 0, absent = 0, tardy = 0, leftEarly = 0
        for record in filteredRecords {
            switch record.status {
            case .present: present += 1
            case .absent: absent += 1
            case .tardy: tardy += 1
            case .leftEarly: leftEarly += 1
            case .unmarked: break
            }
        }
        return (present, absent, tardy, leftEarly, filteredRecords.count)
    }

    // Group records by day
    private func dayKey(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private var groupedByDay: [(day: Date, items: [AttendanceRecord])] {
        let dict = filteredRecords
            .grouped { dayKey($0.date) }
            .mapValues { arr in arr.sorted { lhs, rhs in
                // Sort by student name within a day
                let lhsName = studentsByID[lhs.studentIDUUID ?? UUID()]?.firstName ?? ""
                let rhsName = studentsByID[rhs.studentIDUUID ?? UUID()]?.firstName ?? ""
                return lhsName < rhsName
            }}
        let days = dict.keys.sorted(by: >)
        return days.map { ($0, dict[$0] ?? []) }
    }

    // MARK: - Filter Labels

    private var selectedStudentLabel: String {
        if selectedStudentIDs.isEmpty {
            return "All Students"
        } else if selectedStudentIDs.count == 1, let id = selectedStudentIDs.first,
                  let student = students.first(where: { $0.id == id }) {
            return displayName(for: student)
        } else {
            return "\(selectedStudentIDs.count) Students"
        }
    }

    private var selectedStatusLabel: String {
        if selectedStatuses.isEmpty {
            return "All Statuses"
        } else if selectedStatuses.count == 1, let status = selectedStatuses.first {
            return status.displayName
        } else {
            return "\(selectedStatuses.count) Statuses"
        }
    }

    private func displayName(for student: Student) -> String {
        let first = student.firstName.trimmed()
        let last = student.lastName.trimmed()
        let li = last.first.map { String($0).uppercased() } ?? ""
        return li.isEmpty ? first : "\(first) \(li)."
    }

    // Available statuses (exclude unmarked)
    private var availableStatuses: [AttendanceStatus] {
        AttendanceStatus.allCases.filter { $0 != .unmarked }
    }

    // MARK: - Summary Stats View

    private var summaryStatsView: some View {
        HStack(spacing: 16) {
            statBadge(count: summaryStats.present, label: "Present", color: .green)
            statBadge(count: summaryStats.absent, label: "Absent", color: .red)
            statBadge(count: summaryStats.tardy, label: "Tardy", color: .blue)
            statBadge(count: summaryStats.leftEarly, label: "Left Early", color: .purple)
            Spacer()
            Text("\(summaryStats.total) records")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.02))
    }

    private func statBadge(count: Int, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color.opacity(0.35))
                .frame(width: 10, height: 10)
            Text("\(count)")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            // Student Menu (multi-select)
            Menu {
                Button("All Students") { selectedStudentIDs.removeAll() }
                Divider()
                ForEach(students) { student in
                    Button(action: {
                        if selectedStudentIDs.contains(student.id) {
                            selectedStudentIDs.remove(student.id)
                        } else {
                            selectedStudentIDs.insert(student.id)
                        }
                    }) {
                        HStack {
                            if selectedStudentIDs.contains(student.id) {
                                Image(systemName: "checkmark")
                            }
                            Text(displayName(for: student))
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "person.3")
                    Text(selectedStudentLabel)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            }

            // Status Menu (multi-select)
            Menu {
                Button("All Statuses") { selectedStatuses.removeAll() }
                Divider()
                ForEach(availableStatuses, id: \.self) { status in
                    Button(action: {
                        if selectedStatuses.contains(status) {
                            selectedStatuses.remove(status)
                        } else {
                            selectedStatuses.insert(status)
                        }
                    }) {
                        HStack {
                            if selectedStatuses.contains(status) {
                                Image(systemName: "checkmark")
                            }
                            Text(status.displayName)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                    Text(selectedStatusLabel)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            }

            // Date Range Menu
            Menu {
                ForEach(DateRangeFilter.allCases) { range in
                    Button(action: { selectedDateRange = range }) {
                        HStack {
                            if selectedDateRange == range {
                                Image(systemName: "checkmark")
                            }
                            Text(range.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                    Text(selectedDateRange.rawValue)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            }

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

    // MARK: - Date Formatters

    private static let dayFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }()

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            filterBar
                .padding(.vertical, 8)

            customDateRangePicker

            summaryStatsView

            Divider()

            if filteredRecords.isEmpty {
                ContentUnavailableView(
                    "No Attendance Records",
                    systemImage: "calendar.badge.clock",
                    description: Text("Attendance records will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(groupedByDay, id: \.day) { entry in
                            Section {
                                ForEach(entry.items) { record in
                                    attendanceRow(for: record)
                                }
                            } header: {
                                Text(Self.dayFormatter.string(from: entry.day))
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
    }

    // MARK: - Row

    @ViewBuilder
    private func attendanceRow(for record: AttendanceRecord) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Status indicator
            Circle()
                .fill(record.status.color)
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                // Student name
                if let studentID = record.studentIDUUID, let student = studentsByID[studentID] {
                    Text(displayName(for: student))
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                } else {
                    Text("Unknown Student")
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                // Status and reason
                HStack(spacing: 6) {
                    Text(record.status.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if record.status == .absent && record.absenceReason != .none {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Image(systemName: record.absenceReason.icon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(record.absenceReason.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Note indicator
            if !record.latestUnifiedNoteText.isEmpty {
                Image(systemName: "note.text")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .contentShape(Rectangle())
        .contextMenu {
            // Change status submenu
            Menu {
                ForEach(availableStatuses, id: \.self) { status in
                    Button {
                        updateRecordStatus(record, to: status)
                    } label: {
                        Label(status.displayName, systemImage: status == record.status ? "checkmark" : "circle")
                    }
                    .disabled(status == record.status)
                }
            } label: {
                Label("Change Status", systemImage: "arrow.triangle.2.circlepath")
            }

            if let studentID = record.studentIDUUID {
                #if os(macOS)
                Button {
                    openStudentInNewWindow(studentID)
                } label: {
                    Label("View Student", systemImage: "person.text.rectangle")
                }
                #endif
            }

            Divider()

            Button(role: .destructive) {
                deleteRecord(record)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func updateRecordStatus(_ record: AttendanceRecord, to status: AttendanceStatus) {
        record.status = status
        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save after updating record status: \(error, privacy: .public)")
        }
    }

    private func deleteRecord(_ record: AttendanceRecord) {
        modelContext.delete(record)
        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save after deleting record: \(error, privacy: .public)")
        }
    }
}

#Preview {
    AttendanceLogView()
}
