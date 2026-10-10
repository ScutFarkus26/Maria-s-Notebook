// swiftlint:disable file_length
import SwiftUI
import CoreData

/// Represents a student assignment with optional time
struct SlotAssignment: Identifiable, Equatable {
    let id = UUID()
    var studentID: String
    var timeString: String

    init(studentID: String, timeString: String = "") {
        self.studentID = studentID
        self.timeString = timeString
    }
}

// Sheet for creating or editing a schedule
// swiftlint:disable:next type_body_length
struct ScheduleEditorSheet: View {
    let schedule: CDSchedule?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies

    private var students: [CDStudent] { dependencies.roster.enrolled }

    // Form state
    @State private var name: String = ""
    @State private var notes: String = ""
    @State private var colorHex: String = "#007AFF"
    @State private var icon: String = "calendar"

    // Slot assignments by day: [Weekday: [SlotAssignment]]
    @State private var assignments: [Weekday: [SlotAssignment]] = [:]

    /// The time field being typed in. A day's rows are put in time order when
    /// she leaves a field or presses Return, not on every keystroke.
    @FocusState private var focusedTime: SlotAssignment.ID?

    private var isEditing: Bool { schedule != nil }

    private var isValid: Bool {
        !name.trimmed().isEmpty
    }

    init(schedule: CDSchedule?) {
        self.schedule = schedule
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    Text(isEditing ? "Edit Schedule" : "New Schedule")
                        .font(AppTheme.ScaledFont.titleXLarge)

                    // Basic Info Section
                    basicInfoSection

                    Divider()

                    // Appearance Section
                    appearanceSection

                    Divider()

                    // Weekly CDSchedule Section
                    weeklyScheduleSection
                }
                .padding(24)
            }

            Divider()

            // Bottom bar
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button(isEditing ? "Save" : "Create") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(16)
            .background(.bar)
        }
        #if os(iOS)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        #else
        .frame(minWidth: 600, minHeight: 500)
        #endif
        .onAppear {
            loadExistingData()
        }
        .onChange(of: focusedTime) { previous, _ in
            if let previous, let weekday = weekday(of: previous) {
                sortDay(weekday)
            }
        }
        .saveErrorAlert()
    }

    // MARK: - Basic Info Section

    private var basicInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Schedule Info")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("Name")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("e.g., Reading Support", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Notes (optional)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TextField("Additional notes...", text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3...6)
            }
        }
    }

    // MARK: - Appearance Section

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Appearance")
                .font(.headline)

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Color")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Color", selection: $colorHex) {
                        ForEach(colorOptions, id: \.hex) { option in
                            HStack {
                                Circle()
                                    .fill(Color(hex: option.hex) ?? .blue)
                                    .frame(width: 16, height: 16)
                                Text(option.name)
                            }
                            .tag(option.hex)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 150)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Icon")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Picker("Icon", selection: $icon) {
                        ForEach(iconOptions, id: \.self) { iconName in
                            Label(iconName.replacingOccurrences(of: ".", with: " ").capitalized, systemImage: iconName)
                                .tag(iconName)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }
        }
    }

    // MARK: - Weekly CDSchedule Section

    private var weeklyScheduleSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Weekly Schedule")
                .font(.headline)

            ForEach(Weekday.schoolDays, id: \.self) { weekday in
                dayEditor(for: weekday)
                if weekday != .friday {
                    Divider()
                }
            }
        }
    }

    private func dayEditor(for weekday: Weekday) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(weekday.rawValue)
                    .font(.subheadline.weight(.bold))

                Spacer()

                let count = assignments[weekday]?.count ?? 0
                if count > 0 {
                    Text("\(count) student\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Current assignments
            let dayAssignments = assignments[weekday] ?? []
            if !dayAssignments.isEmpty {
                VStack(spacing: 8) {
                    ForEach(dayAssignments) { assignment in
                        slotRow(assignment: assignment, weekday: weekday)
                    }
                }
            }

            // Add student menu
            Menu {
                ForEach(availableStudents(for: weekday)) { student in
                    Button {
                        addStudent(student.id?.uuidString ?? "", to: weekday)
                    } label: {
                        Text(student.fullName)
                    }
                }

                if availableStudents(for: weekday).isEmpty {
                    Text("All students assigned")
                        .foregroundStyle(.secondary)
                }
            } label: {
                Label("Add Student", systemImage: "plus")
                    .font(.subheadline)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }

    private func slotRow(assignment: SlotAssignment, weekday: Weekday) -> some View {
        HStack(spacing: 12) {
            if let student = students.first(where: { $0.id?.uuidString == assignment.studentID }) {
                Text(student.fullName)
                    .font(.subheadline)
            } else {
                Text("Unknown Student")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Time field
            TextField("Time", text: bindingForTime(assignment: assignment, weekday: weekday), prompt: Text("9:30"))
                .font(.subheadline)
                .textFieldStyle(.roundedBorder)
                .frame(width: 80)
                .focused($focusedTime, equals: assignment.id)
                .onSubmit { sortDay(weekday) }

            Button {
                removeStudent(assignment.studentID, from: weekday)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(AppColors.destructive)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Helpers

    private func bindingForTime(assignment: SlotAssignment, weekday: Weekday) -> Binding<String> {
        Binding(
            get: {
                assignments[weekday]?.first(where: { $0.id == assignment.id })?.timeString ?? ""
            },
            set: { newValue in
                if var dayAssignments = assignments[weekday],
                   let index = dayAssignments.firstIndex(where: { $0.id == assignment.id }) {
                    dayAssignments[index].timeString = newValue
                    assignments[weekday] = dayAssignments
                }
            }
        )
    }

    /// The day `assignmentID` is on.
    private func weekday(of assignmentID: SlotAssignment.ID) -> Weekday? {
        assignments.first { $0.value.contains { $0.id == assignmentID } }?.key
    }

    /// Puts a day's rows in time order (`ScheduleTime`): "1:15" after
    /// "9:30", AM and PM understood, blank times last.
    private func sortDay(_ weekday: Weekday) {
        guard let dayAssignments = assignments[weekday] else { return }
        let sorted = ScheduleSlotWriter.ordered(dayAssignments, by: \.timeString)
        if sorted.map(\.id) != dayAssignments.map(\.id) {
            assignments[weekday] = sorted
        }
    }

    private func availableStudents(for weekday: Weekday) -> [CDStudent] {
        let assignedIDs = Set((assignments[weekday] ?? []).map(\.studentID))
        return students.filter { !assignedIDs.contains($0.id?.uuidString ?? "") }
    }

    private func addStudent(_ studentID: String, to weekday: Weekday) {
        var dayAssignments = assignments[weekday] ?? []
        if !dayAssignments.contains(where: { $0.studentID == studentID }) {
            dayAssignments.append(SlotAssignment(studentID: studentID))
            assignments[weekday] = dayAssignments
        }
    }

    private func removeStudent(_ studentID: String, from weekday: Weekday) {
        var dayAssignments = assignments[weekday] ?? []
        dayAssignments.removeAll { $0.studentID == studentID }
        assignments[weekday] = dayAssignments
    }

    private func loadExistingData() {
        guard let schedule else { return }

        name = schedule.name
        notes = schedule.notes
        colorHex = schedule.colorHex
        icon = schedule.icon

        // One row per child and day (a child on a day twice shows once, and
        // the save keeps one slot), in the order the schedule shows them.
        for (weekday, slotsByStudent) in ScheduleSlotWriter.slotsByDay(of: schedule).kept {
            let slots = slotsByStudent.values.sorted { $0.sortOrder < $1.sortOrder }
            let dayAssignments = slots.map { SlotAssignment(studentID: $0.studentID, timeString: $0.timeString ?? "") }
            assignments[weekday] = ScheduleSlotWriter.ordered(dayAssignments, by: \.timeString)
        }
    }

    private func save() {
        let trimmedName = name.trimmed()
        guard !trimmedName.isEmpty else { return }

        let target: CDSchedule
        if let schedule {
            // Update existing schedule
            schedule.name = trimmedName
            schedule.notes = notes
            schedule.colorHex = colorHex
            schedule.icon = icon
            schedule.touch()
            target = schedule
        } else {
            // Create new schedule
            let newSchedule = CDSchedule(context: viewContext)
            newSchedule.name = trimmedName
            newSchedule.notes = notes
            newSchedule.colorHex = colorHex
            newSchedule.icon = icon
            // CDSchedule(context:) already inserts into context
            target = newSchedule
        }

        // Slots are updated in place, so each child keeps one slot a day.
        let days = assignments.mapValues { day in
            day.map { ScheduleSlotWriter.Entry(studentID: $0.studentID, timeString: $0.timeString) }
        }
        ScheduleSlotWriter.apply(days, to: target, in: viewContext)

        // On failure the coordinator's alert says so and the sheet stays open.
        if dependencies.saveCoordinator.save(viewContext, reason: "Save schedule") {
            dismiss()
        }
    }

    // MARK: - Options

    private var colorOptions: [(name: String, hex: String)] {
        [
            ("Blue", "#007AFF"),
            ("Purple", "#AF52DE"),
            ("Pink", "#FF2D55"),
            ("Red", "#FF3B30"),
            ("Orange", "#FF9500"),
            ("Yellow", "#FFCC00"),
            ("Green", "#34C759"),
            ("Teal", "#5AC8FA"),
            ("Indigo", "#5856D6"),
            ("Brown", "#A2845E"),
            ("Gray", "#8E8E93")
        ]
    }

    private var iconOptions: [String] {
        [
            "calendar",
            "clock",
            "book",
            "book.pages",
            "text.book.closed",
            "graduationcap",
            "pencil.and.ruler",
            "star",
            "heart",
            "person.2",
            "person.3",
            "bubble.left.and.bubble.right",
            "music.note",
            "paintbrush",
            "theatermasks",
            "sportscourt",
            "leaf",
            "globe",
            "lightbulb",
            "hammer"
        ]
    }
}

// The `#Preview` closure is expanded and type-checked in every compiler job
// for the module; a private view is checked once, in this file's job.
private struct ScheduleEditorSheetPreview: View {
    var body: some View {
        ScheduleEditorSheet(schedule: nil)
            .previewEnvironment()
    }
}

#Preview("New Schedule") {
    ScheduleEditorSheetPreview()
}
