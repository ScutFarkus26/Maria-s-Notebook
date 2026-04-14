import SwiftUI
import CoreData

// MARK: - Queue Sidebar (Separate View)

struct MeetingsQueueSidebar: View {
    let studentsNeedingMeeting: [CDStudent]
    let studentsCompleted: [CDStudent]
    @Binding var selectedStudentID: UUID?
    @Binding var searchText: String
    @Binding var showCompletedThisWeek: Bool
    @Binding var daysSinceThreshold: Int
    @Binding var selectedAgeRanges: Set<AgeRange>
    let lastMeetingFor: (CDStudent) -> CDStudentMeeting?
    let onMove: (IndexSet, Int) -> Void
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
        }
    }

    private var completedSection: some View {
        Section("Met Recently (\(studentsCompleted.count))") {
            ForEach(studentsCompleted) { student in
                studentRow(student, showCheckmark: true)
            }
        }
    }

    private func studentRow(_ student: CDStudent, showCheckmark: Bool) -> some View {
        StudentQueueRow(
            student: student,
            lastMeeting: lastMeetingFor(student),
            isSelected: selectedStudentID == student.id,
            showCheckmark: showCheckmark,
            scheduledDate: student.id.flatMap { scheduledMeetingDates[$0] }
        )
        .tag(student.id)
        .contextMenu {
            scheduleMeetingMenu(for: student)
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

        if let onScheduleMeeting {
            Divider()

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

// MARK: - Meeting Threshold Picker

struct MeetingThresholdPicker: View {
    @Binding var days: Int
    @Binding var showCompleted: Bool
    @State private var isExpanded = false

    private let presets = [3, 5, 7, 14, 21, 30]

    var body: some View {
        VStack(spacing: 8) {
            // Top row: threshold pill + show completed toggle
            HStack(spacing: 8) {
                // Tappable pill showing current value
                Button {
                    adaptiveWithAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption)

                        Text("Last \(days)d")
                            .font(.subheadline.weight(.medium))

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(UIConstants.OpacityConstants.medium))
                    )
                    .foregroundStyle(.accent)
                }
                .buttonStyle(.plain)

                // Show completed toggle
                Button {
                    adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                        showCompleted.toggle()
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: showCompleted ? "checkmark.circle.fill" : "checkmark.circle")
                            .font(.caption)

                        Text("Done")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(showCompleted ? Color.green.opacity(UIConstants.OpacityConstants.accent) : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                    )
                    .foregroundStyle(showCompleted ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }

            // Expanded picker
            if isExpanded {
                VStack(spacing: 8) {
                    // Quick presets
                    HStack(spacing: 6) {
                        ForEach(presets, id: \.self) { preset in
                            Button {
                                adaptiveWithAnimation(.easeInOut(duration: 0.15)) {
                                    days = preset
                                }
                            } label: {
                                Text("\(preset)")
                                    .font(.caption.weight(days == preset ? .semibold : .regular))
                                    .frame(width: 28, height: 28)
                                    .background(
                                        Circle()
                                            .fill(days == preset ? Color.accentColor : Color.primary.opacity(UIConstants.OpacityConstants.veryFaint))
                                    )
                                    .foregroundStyle(days == preset ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // Fine-tune stepper
                    HStack(spacing: 12) {
                        Button {
                            if days > 1 { days -= 1 }
                        } label: {
                            Image(systemName: "minus")
                                .font(.caption.weight(.medium))
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)))
                        }
                        .buttonStyle(.plain)
                        .disabled(days <= 1)

                        Text("\(days) day\(days == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 60)

                        Button {
                            if days < 90 { days += 1 }
                        } label: {
                            Image(systemName: "plus")
                                .font(.caption.weight(.medium))
                                .frame(width: 24, height: 24)
                                .background(Circle().fill(Color.primary.opacity(UIConstants.OpacityConstants.veryFaint)))
                        }
                        .buttonStyle(.plain)
                        .disabled(days >= 90)
                    }
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .scale(scale: 0.95, anchor: .top)))
            }
        }
        .frame(maxWidth: .infinity)
        .listRowBackground(Color.clear)
    }
}

// MARK: - CDStudent Queue Row

struct StudentQueueRow: View {
    let student: CDStudent
    let lastMeeting: CDStudentMeeting?
    var isSelected: Bool = false
    var showCheckmark: Bool = false
    var scheduledDate: Date?

    @Environment(\.managedObjectContext) private var viewContext

    private var daysSinceLastMeeting: Int? {
        guard let lastMeeting else { return nil }
        return Calendar.current.dateComponents([.day], from: lastMeeting.date ?? Date(), to: Date()).day
    }

    private var isAbsentToday: Bool {
        guard let studentID = student.id else { return false }
        return viewContext.attendanceStatus(for: studentID, on: Date()) == .absent
    }

    var body: some View {
        HStack(spacing: 10) {
            StudentAvatarView(student: student, size: 36)
                .overlay(
                    Circle()
                        .stroke(isAbsentToday ? Color.red : Color.clear, lineWidth: 1.5)
                )

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
