import SwiftUI
import SwiftData
import OSLog

// swiftlint:disable:next type_body_length
struct MeetingsLogView: View {
    private static let logger = Logger.app_
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar

    // Test student filtering
    @AppStorage(UserDefaultsKeys.generalShowTestStudents) private var showTestStudents: Bool = false
    @AppStorage(UserDefaultsKeys.generalTestStudentNames)
    private var testStudentNamesRaw: String = "Danny De Berry,Lil Dan D"

    @Query(sort: [SortDescriptor(\StudentMeeting.date, order: .reverse)])
    private var allMeetings: [StudentMeeting]

    @Query(sort: Student.sortByName)
    private var studentsRaw: [Student]
    // DEDUPLICATION: CloudKit sync can create duplicate records with the same ID.
    // Filter out test students when setting is disabled
    private var students: [Student] {
        TestStudentsFilter.filterVisible(studentsRaw.uniqueByID, show: showTestStudents, namesRaw: testStudentNamesRaw)
    }

    // Filter state
    @State private var selectedStudentIDs: Set<UUID> = []
    @State private var selectedCompletion: CompletionFilter = .all
    @State private var searchText: String = ""
    @State private var selectedAgeRanges: Set<AgeRange> = []

    enum CompletionFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case completed = "Completed"
        case pending = "Pending"

        var id: String { rawValue }
    }

    // Maps for quick lookup
    // Use uniquingKeysWith to handle CloudKit sync duplicates
    private var studentsByID: [UUID: Student] {
        Dictionary(students.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    // Filtered meetings
    private var filteredMeetings: [StudentMeeting] {
        allMeetings.filter { meeting in
            // Student filter
            if !selectedStudentIDs.isEmpty {
                guard let studentID = meeting.studentIDUUID else { return false }
                if !selectedStudentIDs.contains(studentID) { return false }
            }

            // Age filter
            if !selectedAgeRanges.isEmpty {
                guard let studentID = meeting.studentIDUUID,
                      let student = studentsByID[studentID] else { return false }
                if !AgeRange.matchesAny(student.birthday, in: selectedAgeRanges) { return false }
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
        let dict = filteredMeetings
            .grouped { dayKey($0.date) }
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
    
    private var selectedAgeLabel: String {
        if selectedAgeRanges.isEmpty {
            return "All Ages"
        } else if selectedAgeRanges.count == 1, let first = selectedAgeRanges.first {
            return first.rawValue
        } else {
            return "\(selectedAgeRanges.count) Ages"
        }
    }

    private func displayName(for student: Student) -> String {
        let first = student.firstName.trimmed()
        let last = student.lastName.trimmed()
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
                    }, label: {
                        HStack {
                            if selectedStudentIDs.contains(student.id) {
                                Image(systemName: "checkmark")
                            }
                            Text(displayName(for: student))
                        }
                    })
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

            // Age Range Menu (multi-select)
            Menu {
                Button("All Ages") { selectedAgeRanges.removeAll() }
                Divider()
                ForEach(AgeRange.allCases) { range in
                    Button(action: {
                        if selectedAgeRanges.contains(range) {
                            selectedAgeRanges.remove(range)
                        } else {
                            selectedAgeRanges.insert(range)
                        }
                    }, label: {
                        HStack {
                            if selectedAgeRanges.contains(range) {
                                Image(systemName: "checkmark")
                            }
                            Text(range.rawValue)
                        }
                    })
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                    Text(selectedAgeLabel)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            selectedAgeRanges.isEmpty
                                ? Color.primary.opacity(0.05)
                                : Color.accentColor.opacity(0.12)
                        )
                )
                .foregroundStyle(selectedAgeRanges.isEmpty ? Color.primary : Color.accentColor)
            }

            // Completion Menu
            Menu {
                ForEach(CompletionFilter.allCases) { filter in
                    Button(action: { selectedCompletion = filter }, label: {
                        HStack {
                            if selectedCompletion == filter {
                                Image(systemName: "checkmark")
                            }
                            Text(filter.rawValue)
                        }
                    })
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
    // swiftlint:disable:next function_body_length
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
                        .font(AppTheme.ScaledFont.bodySemibold)
                } else {
                    Text("Unknown Student")
                        .font(AppTheme.ScaledFont.bodySemibold)
                        .foregroundStyle(.secondary)
                }

                // Focus area (if present)
                if !meeting.focus.trimmed().isEmpty {
                    Text(meeting.focus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                // Show indicators for content
                HStack(spacing: 8) {
                    if !meeting.reflection.trimmed().isEmpty {
                        Label("Reflection", systemImage: "text.quote")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !meeting.requests.trimmed().isEmpty {
                        Label("Requests", systemImage: "hand.raised")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    if !meeting.guideNotes.trimmed().isEmpty {
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
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                toggleMeetingCompletion(meeting)
            } label: {
                Label(
                    meeting.completed ? "Mark as Pending" : "Mark as Completed",
                    systemImage: meeting.completed ? "circle" : "checkmark.circle"
                )
            }

            if let studentID = meeting.studentIDUUID {
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
                deleteMeeting(meeting)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func toggleMeetingCompletion(_ meeting: StudentMeeting) {
        meeting.completed.toggle()
        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save after toggling meeting completion: \(error, privacy: .public)")
        }
    }

    private func deleteMeeting(_ meeting: StudentMeeting) {
        modelContext.delete(meeting)
        do {
            try modelContext.save()
        } catch {
            Self.logger.warning("Failed to save after deleting meeting: \(error, privacy: .public)")
        }
    }
}

#Preview {
    MeetingsLogView()
}
