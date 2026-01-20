import SwiftUI
import SwiftData

struct MeetingsLogView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    @Query(sort: [SortDescriptor(\StudentMeeting.date, order: .reverse)])
    private var allMeetings: [StudentMeeting]

    @Query(sort: [SortDescriptor(\Student.firstName), SortDescriptor(\Student.lastName)])
    private var students: [Student]

    // Filter state
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var selectedCompletion: CompletionFilter = .all
    @State private var searchText: String = ""

    enum CompletionFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case completed = "Completed"
        case pending = "Pending"

        var id: String { rawValue }
    }

    // Maps for quick lookup
    private var studentsByID: [UUID: Student] {
        Dictionary(uniqueKeysWithValues: students.map { ($0.id, $0) })
    }

    // Filtered meetings
    private var filteredMeetings: [StudentMeeting] {
        allMeetings.filter { meeting in
            // Student filter
            if !selectedStudentIDs.isEmpty {
                guard let studentID = meeting.studentIDUUID else { return false }
                if !selectedStudentIDs.contains(studentID) { return false }
            }

            // Completion filter
            switch selectedCompletion {
            case .all:
                break
            case .completed:
                if !meeting.completed { return false }
            case .pending:
                if meeting.completed { return false }
            }

            // Search filter (search student name, focus, or reflection)
            if !searchText.isEmpty {
                let query = searchText.lowercased()
                var matches = false

                if let studentID = meeting.studentIDUUID,
                   let student = studentsByID[studentID] {
                    let name = displayName(for: student).lowercased()
                    if name.contains(query) { matches = true }
                }

                if meeting.focus.lowercased().contains(query) { matches = true }
                if meeting.reflection.lowercased().contains(query) { matches = true }
                if meeting.requests.lowercased().contains(query) { matches = true }

                if !matches { return false }
            }

            return true
        }
    }

    // Group meetings by day
    private func dayKey(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    private var groupedByDay: [(day: Date, items: [StudentMeeting])] {
        let dict = Dictionary(grouping: filteredMeetings) { meeting in
            dayKey(meeting.date)
        }
        .mapValues { arr in arr.sorted { lhs, rhs in lhs.date > rhs.date }}
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

    private func displayName(for student: Student) -> String {
        let first = student.firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = student.lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let li = last.first.map { String($0).uppercased() } ?? ""
        return li.isEmpty ? first : "\(first) \(li)."
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

            // Completion Menu
            Menu {
                ForEach(CompletionFilter.allCases) { filter in
                    Button(action: { selectedCompletion = filter }) {
                        HStack {
                            if selectedCompletion == filter {
                                Image(systemName: "checkmark")
                            }
                            Text(filter.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle")
                    Text(selectedCompletion.rawValue)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.05)))
            }

            Spacer()
        }
        .padding(.horizontal, 12)
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
        VStack(spacing: 8) {
            filterBar

            if filteredMeetings.isEmpty {
                ContentUnavailableView(
                    "No Meetings",
                    systemImage: "person.2.circle",
                    description: Text("Student meetings will appear here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(groupedByDay, id: \.day) { entry in
                            Section {
                                ForEach(entry.items) { meeting in
                                    meetingRow(for: meeting)
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
    private func meetingRow(for meeting: StudentMeeting) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Completion indicator
            Image(systemName: meeting.completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(meeting.completed ? .green : .secondary)
                .font(.system(size: 16))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                // Student name
                if let studentID = meeting.studentIDUUID, let student = studentsByID[studentID] {
                    Text(displayName(for: student))
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                } else {
                    Text("Unknown Student")
                        .font(.system(size: AppTheme.FontSize.body, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }

                // Focus area (if present)
                if !meeting.focus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(meeting.focus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Show indicators for content
                HStack(spacing: 8) {
                    if !meeting.reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label("Reflection", systemImage: "text.quote")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !meeting.requests.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label("Requests", systemImage: "hand.raised")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !meeting.guideNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Label("Notes", systemImage: "note.text")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }
}

#Preview {
    MeetingsLogView()
}
