// ScheduleBlockSheet.swift
// Adding or editing one block: its lane, its days (several for a new
// block), start, length in 5-minute steps, title and note. A room's block
// can name who teaches it (a person's lane, or anyone else by name); a
// person's block can list the children she takes. Saving or deleting a block
// that repeats asks Only This Day or This Day and After, the way Calendar
// asks about a repeating event.

import SwiftUI

struct ScheduleBlockSheet: View {

    enum Mode: Equatable {
        /// A new weekly block.
        case new(laneID: UUID?, weekday: Weekday)
        /// Add to This Day: a one-off on `day`.
        case oneOff(laneID: UUID?, day: Date)
        /// An existing block, as `day` shows it.
        case edit(block: ScheduleDay.Block, day: Date, repeats: Bool)
    }

    /// Who teaches a room's block.
    enum Teacher: Hashable {
        case none
        case lane(UUID)
        case someoneElse
    }

    let mode: Mode
    let model: SchedulesPageModel
    let students: [CDStudent]

    @Environment(\.dismiss) private var dismiss

    @State private var laneID: UUID?
    @State private var weekdays: Set<Weekday> = []
    @State private var start = Date()
    @State private var length = 30
    @State private var title = ""
    @State private var note = ""
    @State private var teacher: Teacher = .none
    @State private var teacherName = ""
    @State private var childIDs: Set<UUID> = []
    @State private var showingChildren = false
    @State private var question: ScheduleScopeQuestion?
    @State private var loaded = false

    private var lane: TimetableLaneSnapshot? { model.lanes.first { $0.id == laneID } }

    private var day: Date {
        switch mode {
        case .new: model.day
        case .oneOff(_, let day), .edit(_, let day, _): day
        }
    }

    private var isEditing: Bool { if case .edit = mode { true } else { false } }

    private var navigationTitle: String {
        switch mode {
        case .new: "New Block"
        case .oneOff: "Add to This Day"
        case .edit: "Edit Block"
        }
    }

    private var canSave: Bool {
        guard laneID != nil, !title.trimmed().isEmpty else { return false }
        if case .new = mode { return !weekdays.isEmpty }
        return true
    }

    private var dayText: String { day.formatted(.dateTime.weekday(.wide).month(.wide).day()) }

    var body: some View {
        NavigationStack {
            Form {
                laneSection
                if case .new = mode { daysSection }
                timeSection
                detailsSection
                if lane?.kind == .room { teacherSection }
                if lane?.kind == .person { childrenSection }
                if isEditing {
                    Section {
                        Button("Delete Block", role: .destructive) { askOrDelete() }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(navigationTitle)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Add") { askOrSave() }
                        .disabled(!canSave)
                }
            }
            .scheduleScopeDialog($question) { asked, scope in
                finish(asked.action == .delete ? .delete : .change, scope)
            }
        }
        .onAppear(perform: load)
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    // MARK: - Sections

    private var laneSection: some View {
        Section {
            Picker("Lane", selection: $laneID) {
                ForEach(model.editableLanes) { lane in
                    Text(lane.name).tag(Optional(lane.id))
                }
            }
            .disabled(isEditing)
        } footer: {
            if case .oneOff = mode {
                Text("Only on \(dayText). Use it for an assembly, a trip or an early dismissal.")
            }
        }
    }

    private var daysSection: some View {
        Section("Days") {
            HStack(spacing: 6) {
                ForEach(Weekday.schoolDays) { weekday in
                    let isOn = weekdays.contains(weekday)
                    Button {
                        if isOn { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
                    } label: {
                        Text(weekday.shortName)
                            .font(AppTheme.ScaledFont.captionSemibold)
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.bordered)
                    .tint(isOn ? .accentColor : .secondary)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
    }

    private var timeSection: some View {
        Section("Time") {
            DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)
            Stepper(value: $length, in: 5...480, step: 5) {
                LabeledContent("Length", value: Self.lengthText(length))
            }
        }
    }

    private var detailsSection: some View {
        Section("Details") {
            TextField("Title", text: $title, prompt: Text("Math, Recess, Assembly"))
            TextField("Note (optional)", text: $note, axis: .vertical)
                .lineLimit(1...4)
        }
    }

    private var teacherSection: some View {
        Section("Who Teaches") {
            Picker("Teacher", selection: $teacher) {
                Text("No One").tag(Teacher.none)
                ForEach(model.personLanes) { person in
                    Text(person.name).tag(Teacher.lane(person.id))
                }
                Text("Someone Else…").tag(Teacher.someoneElse)
            }
            if teacher == .someoneElse {
                TextField("Name", text: $teacherName, prompt: Text("Their name"))
            }
        }
    }

    private var childrenSection: some View {
        Section("Children") {
            let chosen = students.filter { $0.id.map(childIDs.contains) ?? false }
            if chosen.isEmpty {
                Text("No children")
                    .foregroundStyle(.secondary)
            } else {
                Text(chosen.map(\.shortName).joined(separator: ", "))
            }
            Button("Choose Children…") { showingChildren = true }
                .popover(isPresented: $showingChildren) {
                    StudentPickerPopover(
                        students: students, selectedIDs: $childIDs, onDone: { showingChildren = false },
                        allowsCreatingStudents: false
                    )
                }
        }
    }
}

// MARK: - Values and saving

extension ScheduleBlockSheet {

    static func lengthText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        switch (hours, rest) {
        case (0, _): return "\(rest) min"
        case (_, 0): return hours == 1 ? "1 hr" : "\(hours) hr"
        default: return "\(hours) hr \(rest) min"
        }
    }

    private var values: TimetableBlockValues {
        let isRoom = lane?.kind == .room
        let teacherLane: UUID? = if isRoom, case .lane(let id) = teacher { id } else { nil }
        let name = isRoom && teacher == .someoneElse ? teacherName.trimmed() : ""
        let children = lane?.kind == .person
            ? students.compactMap { $0.id }.filter(childIDs.contains).map(\.uuidString)
            : []
        return TimetableBlockValues(
            startMinute: TimetableDay.minute(of: start, calendar: model.calendar),
            lengthMinutes: length,
            title: title.trimmed(),
            note: note.trimmed(),
            teacherLaneID: teacherLane,
            teacherName: name,
            studentIDs: children
        )
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        let fallbackLane = model.editableLanes.first?.id
        var initial = TimetableBlockValues(startMinute: 9 * 60)
        switch mode {
        case .new(let lane, let weekday):
            laneID = lane ?? fallbackLane
            weekdays = [weekday]
        case .oneOff(let lane, _):
            laneID = lane ?? fallbackLane
        case .edit(let block, _, _):
            laneID = block.laneID
            initial = block.values
        }
        start = model.calendar.date(
            bySettingHour: initial.startMinute / 60, minute: initial.startMinute % 60, second: 0, of: day
        ) ?? day
        length = max(5, (initial.lengthMinutes / 5) * 5)
        title = initial.title
        note = initial.note
        if let id = initial.teacherLaneID {
            teacher = .lane(id)
        } else if !initial.teacherName.trimmed().isEmpty {
            teacher = .someoneElse
            teacherName = initial.teacherName
        }
        childIDs = Set(initial.studentIDs.compactMap(UUID.init(uuidString:)))
    }

    // MARK: - Saving

    private func askOrSave() {
        if case .edit(let block, let day, true) = mode {
            question = ScheduleScopeQuestion(action: .change, blockID: block.id, day: day)
            return
        }
        finish(.change, .everyWeek)
    }

    private func askOrDelete() {
        if case .edit(let block, let day, true) = mode {
            question = ScheduleScopeQuestion(action: .delete, blockID: block.id, day: day)
            return
        }
        finish(.delete, .everyWeek)
    }

    private func finish(_ action: ScheduleScopeQuestion.Action, _ scope: TimetableService.EditScope) {
        question = nil
        guard let laneID else { return }
        let saved: Bool
        switch (mode, action) {
        case (.new, _):
            saved = model.addBlock(values, laneID: laneID, on: Weekday.schoolDays.filter(weekdays.contains))
        case (.oneOff(_, let day), _):
            saved = model.addOneOff(values, laneID: laneID, on: day)
        case (.edit(let block, let day, _), .change):
            saved = model.edit(blockID: block.id, to: values, scope: scope, on: day)
        case (.edit(let block, let day, _), .delete):
            saved = model.delete(blockID: block.id, scope: scope, on: day)
        }
        // On failure the save alert says so and the sheet stays open.
        if saved { dismiss() }
    }
}
