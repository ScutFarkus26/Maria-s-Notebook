import SwiftUI
import CoreData

struct MeetingsLogView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    @Environment(\.calendar) private var calendar

    // Test student filtering
    @TestStudentVisibility private var testStudents

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDStudentMeeting.date, ascending: false)]
    )
    private var allMeetings: FetchedResults<CDStudentMeeting>

    // Filter out test students when setting is disabled.
    // All students, not enrolled-only: this log spans all time, so former
    // students' meeting history must keep resolving.
    private var students: [CDStudent] {
        TestStudentsFilter.filterVisible(
            dependencies.roster.all,
            show: testStudents.show,
            namesRaw: testStudents.namesRaw
        )
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
    private var studentsByID: [UUID: CDStudent] {
        Dictionary(students.compactMap { s in s.id.map { ($0, s) } }, uniquingKeysWith: { first, _ in first })
    }

    // Filtered meetings
    private var filteredMeetings: [CDStudentMeeting] {
        allMeetings.filter { meeting in
            // CDStudent filter
            if !selectedStudentIDs.isEmpty {
                guard let studentID = meeting.studentIDUUID else { return false }
                if !selectedStudentIDs.contains(studentID) { return false }
            }

            // Age filter
            if !selectedAgeRanges.isEmpty {
                guard let studentID = meeting.studentIDUUID,
                      let student = studentsByID[studentID] else { return false }
                if !AgeRange.matchesAny(student.birthday ?? Date(), in: selectedAgeRanges) { return false }
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
                    let name = student.shortName.lowercased()
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

    private var groupedByDay: [(day: Date, items: [CDStudentMeeting])] {
        let dict = filteredMeetings
            .grouped { dayKey($0.date ?? Date.distantPast) }
            .mapValues { arr in arr.sorted { lhs, rhs in (lhs.date ?? .distantPast) > (rhs.date ?? .distantPast) }}
        let days = dict.keys.sorted(by: >)
        return days.map { ($0, dict[$0] ?? []) }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            MultiSelectFilterMenu(
                items: students,
                selection: $selectedStudentIDs,
                id: { $0.id },
                label: { $0.shortName },
                summary: FilterSelectionSummary(allLabel: "All Students"),
                systemImage: "person.3"
            )

            MultiSelectFilterMenu(
                items: AgeRange.allCases,
                selection: $selectedAgeRanges,
                label: { $0.rawValue },
                summary: FilterSelectionSummary(allLabel: "All Ages"),
                systemImage: "calendar.badge.clock",
                accentsSelection: true
            )

            SingleSelectFilterMenu(
                items: CompletionFilter.allCases,
                selection: $selectedCompletion,
                label: { $0.rawValue },
                systemImage: "checkmark.circle"
            )

            Spacer()
        }
        .padding(.horizontal, 12)
    }

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
    }

    // MARK: - Row

    @ViewBuilder
    // swiftlint:disable:next function_body_length
    private func meetingRow(for meeting: CDStudentMeeting) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Completion indicator
            Image(systemName: meeting.completed ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(meeting.completed ? .green : .secondary)
                .font(.system(size: 16))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                // CDStudent name
                if let studentID = meeting.studentIDUUID, let student = studentsByID[studentID] {
                    Text(student.shortName)
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
                .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
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

    private func toggleMeetingCompletion(_ meeting: CDStudentMeeting) {
        meeting.completed.toggle()
        dependencies.saveCoordinator.save(viewContext, reason: "Toggle meeting completion")
    }

    private func deleteMeeting(_ meeting: CDStudentMeeting) {
        viewContext.delete(meeting)
        dependencies.saveCoordinator.save(viewContext, reason: "Delete meeting")
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct MeetingsLogViewPreview: View {
    var body: some View {
        MeetingsLogView()
            .previewEnvironment()
    }
}

#Preview {
    MeetingsLogViewPreview()
}
