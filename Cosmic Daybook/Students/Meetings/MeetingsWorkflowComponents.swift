import SwiftUI
import CoreData
import UniformTypeIdentifiers

// MARK: - Queue Sidebar (Separate View)

struct MeetingsQueueSidebar: View {
    let studentsNeedingMeeting: [CDStudent]
    var studentsAbsentToday: [CDStudent] = []
    let studentsCompleted: [CDStudent]
    @Binding var selectedStudentID: UUID?
    @Binding var searchText: String
    @Binding var showCompletedThisWeek: Bool
    @Binding var daysSinceThreshold: Int
    @Binding var selectedAgeRanges: Set<AgeRange>
    let lastMeetingFor: (CDStudent) -> CDStudentMeeting?
    let onMove: (IndexSet, Int) -> Void
    /// Puts a recently-met student back into the queue at the given index
    /// (nil = top). Nil disables dragging Met Recently rows into the queue.
    var onRequeue: (@MainActor (UUID, Int?) -> Void)?
    var scheduledMeetingDates: [UUID: Date] = [:]
    var onScheduleMeeting: ((CDStudent, Date?) -> Void)?
    var onPickMeetingDate: ((CDStudent) -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
                TextField("Search students", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(UIConstants.OpacityConstants.trace))
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, 8)

            List(selection: $selectedStudentID) {
                filtersSection
                needsMeetingSection
                if !studentsAbsentToday.isEmpty {
                    absentTodaySection
                }
                if showCompletedThisWeek {
                    completedSection
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .navigationBarTrailing) {
                EditButton()
            }
            #endif
        }
    }

    private var filtersSection: some View {
        Section {
            MeetingThresholdPicker(days: $daysSinceThreshold, showCompleted: $showCompletedThisWeek)
            AgeFilterPicker(selectedAgeRanges: $selectedAgeRanges)
        }
    }

    private var needsMeetingSection: some View {
        Section("Needs Meeting (\(studentsNeedingMeeting.count))") {
            ForEach(studentsNeedingMeeting) { student in
                studentRow(student, showCheckmark: false)
            }
            .onMove(perform: searchText.isEmpty ? onMove : nil)
            .onInsert(of: [Self.dragType]) { index, providers in
                insertDroppedStudents(providers, at: index)
            }
        }
    }

    /// Met Recently rows are dragged as their student id, so a drop into
    /// Needs Meeting can name the student without carrying the object.
    private static let dragType = UTType.plainText

    private func insertDroppedStudents(_ providers: [NSItemProvider], at index: Int) {
        guard let onRequeue else { return }
        let droppable = Set(studentsCompleted.compactMap(\.id))
        for provider in providers {
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                guard let string = object as? String,
                      let id = UUID(uuidString: string),
                      droppable.contains(id) else { return }
                Task { @MainActor in
                    onRequeue(id, index)
                }
            }
        }
    }

    private var absentTodaySection: some View {
        Section("Absent Today (\(studentsAbsentToday.count))") {
            ForEach(studentsAbsentToday) { student in
                studentRow(student, showCheckmark: false)
            }
        }
    }

    private var completedSection: some View {
        Section("Met Recently (\(studentsCompleted.count))") {
            ForEach(studentsCompleted) { student in
                if onRequeue != nil, let id = student.id {
                    studentRow(student, showCheckmark: true)
                        .onDrag { NSItemProvider(object: id.uuidString as NSString) }
                } else {
                    studentRow(student, showCheckmark: true)
                }
            }
        }
    }

    // The tag must be a non-optional UUID: List(selection: Binding<UUID?>) only
    // matches tags of exactly UUID, so tagging with the optional `student.id`
    // makes every row silently unselectable.
    @ViewBuilder
    private func studentRow(_ student: CDStudent, showCheckmark: Bool) -> some View {
        let row = StudentQueueRow(
            student: student,
            lastMeeting: lastMeetingFor(student),
            isSelected: selectedStudentID == student.id,
            showCheckmark: showCheckmark,
            scheduledDate: student.id.flatMap { scheduledMeetingDates[$0] }
        )
        .contextMenu {
            scheduleMeetingMenu(for: student)
        }
        if let id = student.id {
            row.tag(id)
        } else {
            row.selectionDisabled()
        }
    }

    // MARK: - Schedule Meeting Context Menu

    @ViewBuilder
    private func scheduleMeetingMenu(for student: CDStudent) -> some View {
        let scheduledDate = student.id.flatMap { scheduledMeetingDates[$0] }

        Button {
            selectedStudentID = student.id
        } label: {
            Label("Start Meeting", systemImage: "play.fill")
        }

        if let onRequeue, let id = student.id, studentsCompleted.contains(where: { $0.id == id }) {
            Button {
                onRequeue(id, nil)
            } label: {
                Label("Move to Needs Meeting", systemImage: "arrow.up.to.line")
            }
        }

        if let onScheduleMeeting {
            Divider()
            scheduleSubmenu(for: student, scheduledDate: scheduledDate, onScheduleMeeting: onScheduleMeeting)
        }
    }

    @ViewBuilder
    private func scheduleSubmenu(
        for student: CDStudent,
        scheduledDate: Date?,
        onScheduleMeeting: @escaping (CDStudent, Date?) -> Void
    ) -> some View {
        Menu {
            Button {
                onScheduleMeeting(student, AppCalendar.startOfDay(Date()))
            } label: {
                Label("Today", systemImage: "calendar")
            }

            Button {
                onScheduleMeeting(student, AppCalendar.addingDays(1, to: Date()))
            } label: {
                Label("Tomorrow", systemImage: "calendar.badge.clock")
            }

            if let onPickDate = onPickMeetingDate {
                Button {
                    onPickDate(student)
                } label: {
                    Label("Pick a Day\u{2026}", systemImage: "calendar.badge.plus")
                }
            }

            if scheduledDate != nil {
                Divider()

                Button(role: .destructive) {
                    onScheduleMeeting(student, nil)
                } label: {
                    Label("Clear", systemImage: "calendar.badge.minus")
                }
            }
        } label: {
            if let date = scheduledDate {
                Label(
                    "Meeting \(MeetingsQueueSidebar.scheduledDateLabel(date))",
                    systemImage: "person.crop.circle.badge.clock"
                )
            } else {
                Label("Schedule Meeting", systemImage: "person.crop.circle.badge.clock")
            }
        }
    }

    private static func scheduledDateLabel(_ date: Date) -> String {
        if AppCalendar.isSameDay(date, Date()) {
            return "(Today)"
        } else if AppCalendar.isSameDay(date, AppCalendar.addingDays(1, to: Date())) {
            return "(Tomorrow)"
        } else {
            return "(\(DateFormatters.mediumDate.string(from: date)))"
        }
    }
}

// MARK: - CDStudent Queue Row

struct StudentQueueRow: View {
    let student: CDStudent
    let lastMeeting: CDStudentMeeting?
    var isSelected: Bool = false
    var showCheckmark: Bool = false
    var scheduledDate: Date?

    private var daysSinceLastMeeting: Int? {
        guard let lastMeeting else { return nil }
        // Clamped to the school-year counter epoch so last spring's meeting doesn't read
        // "104 days ago" on the first morning of the new year.
        let from = SchoolYearCounters.countFrom(lastMeeting.date ?? Date())
        return AppCalendar.shared.dateComponents([.day], from: from, to: Date()).day
    }

    var body: some View {
        HStack(spacing: 10) {
            StudentAvatarView(student: student, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(StudentFormatter.displayName(for: student))
                    .font(.subheadline.weight(.medium))

                if let days = daysSinceLastMeeting {
                    Text("\(days) days ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No prior meetings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let date = scheduledDate {
                Text(Self.shortDateLabel(date))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.teal))
            }

            if showCheckmark {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.success)
            }
        }
        .padding(.vertical, 4)
    }

    private static func shortDateLabel(_ date: Date) -> String {
        if AppCalendar.isSameDay(date, Date()) {
            return "Today"
        } else if AppCalendar.isSameDay(date, AppCalendar.addingDays(1, to: Date())) {
            return "Tomorrow"
        } else {
            return DateFormatters.shortMonthDay.string(from: date)
        }
    }
}
