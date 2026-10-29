// SchedulesView.swift
// The Schedules page: our class, the adolescent room, the guide's planned
// lessons and Morah Devora, side by side, for a day or a week. It replaced
// the recurring per-child schedules page (Plan - Schedules, decision 1).
//
// The header carries the day with its Hebrew date and parsha, the day and
// week controls, a "1 change today" chip and the day's gentle warnings (a tap
// scrolls to the lesson). Mac and iPad show the lanes side by side; iPhone,
// one list with a lane filter. The page reads and edits through
// `SchedulesPageModel`.

import SwiftUI

struct SchedulesView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dependencies) private var dependencies
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// Made once the context is known; remade when the classroom changes.
    @State private var model: SchedulesPageModel?

    var body: some View {
        Group {
            if let model {
                SchedulesPage(model: model, students: dependencies.roster.enrolled, isCompact: isCompact)
            } else {
                Color.clear
            }
        }
        .navigationTitle("Schedules")
        .task(id: ObjectIdentifier(viewContext)) {
            let model = SchedulesPageModel(context: viewContext, saveCoordinator: dependencies.saveCoordinator)
            model.studentNames = Self.names(dependencies.roster.enrolled)
            model.reload()
            self.model = model
        }
        .onChange(of: dependencies.roster.enrolled) { _, students in
            model?.studentNames = Self.names(students)
        }
        .onReceive(SchedulesPageModel.inputChanges()) { _ in
            model?.scheduleReload()
        }
        .saveErrorAlert()
    }

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    /// Short names by upper-cased student ID.
    static func names(_ students: [CDStudent]) -> [String: String] {
        Dictionary(
            students.compactMap { student in student.id.map { ($0.uuidString.uppercased(), student.shortName) } },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

/// The page itself, once its model is made.
struct SchedulesPage: View {
    @Bindable var model: SchedulesPageModel
    let students: [CDStudent]
    let isCompact: Bool

    /// The sheet showing, if any.
    enum Sheet: Identifiable {
        case block(ScheduleBlockSheet.Mode)
        case lanes
        case copyDay(Weekday, TimetableLaneSnapshot)

        var id: String {
            switch self {
            case .block(let mode): "block-\(String(describing: mode))"
            case .lanes: "lanes"
            case .copyDay(let weekday, let lane): "copy-\(weekday.rawValue)-\(lane.id)"
            }
        }
    }

    @State private var sheet: Sheet?
    @State private var showingAddPerson = false
    @State private var newPersonName = ""
    /// A delete asked from a block's menu, waiting on Only This Day or This Day and After.
    @State private var deleteQuestion: ScheduleScopeQuestion?
    @State private var laneFilter: UUID?
    @State private var position = ScrollPosition(edge: .top)
    @State private var highlightedRowID: String?
    @State private var scrollTarget: String?

    var body: some View {
        VStack(spacing: 0) {
            ViewHeader(title: "Schedules") { controls }
            Divider()
            if model.hasLanes {
                SchedulesSubheader(model: model, onWarning: showWarning)
                Divider()
                content
            } else {
                setUpState
            }
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .block(let mode):
                ScheduleBlockSheet(mode: mode, model: model, students: students)
            case .lanes:
                ScheduleLanesSheet(model: model) { askForPerson() }
            case .copyDay(let weekday, let lane):
                ScheduleCopyDaySheet(source: weekday, laneName: lane.name) { targets in
                    model.copyDay(weekday, laneID: lane.id, to: targets)
                }
            }
        }
        .alert("Add a Person", isPresented: $showingAddPerson) {
            TextField("Name", text: $newPersonName)
            Button("Add") { model.addPerson(named: newPersonName) }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("A lane for someone whose schedule you keep, such as your co-teacher.")
        }
        .scheduleScopeDialog($deleteQuestion) { asked, scope in
            model.delete(blockID: asked.blockID, scope: scope, on: asked.day)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        let style = ScheduleItemStyle(lanesByID: model.lanesByID, names: model.studentNames, isToday: model.isToday)
        switch model.mode {
        case .day:
            if isCompact {
                ScheduleDayList(
                    day: model.resolved, style: style, actions: actions, laneFilter: laneFilter,
                    highlightedRowID: highlightedRowID, scrollTarget: scrollTarget
                )
            } else {
                ScheduleDayGrid(
                    day: model.resolved, style: style, actions: actions, highlightedRowID: highlightedRowID,
                    position: $position
                )
            }
        case .week:
            if let lane = model.weekLane {
                ScheduleWeekView(
                    columns: model.week, lane: lane, lanesByID: model.lanesByID, names: model.studentNames,
                    isToday: model.isToday(_:), isCompact: isCompact, actions: actions,
                    onCopyDay: { weekday in sheet = .copyDay(weekday, lane) },
                    onShowDay: { day in
                        model.day = day
                        model.mode = .day
                    }
                )
            }
        }
    }

    private var actions: ScheduleActions {
        ScheduleActions(
            edit: { block, day in
                sheet = .block(.edit(block: block, day: day, repeats: model.isRepeating(blockID: block.id)))
            },
            cancelThisDay: { block, day in model.cancel(blockID: block.id, on: day) },
            undoChange: { block, day in model.undoChange(blockID: block.id, on: day) },
            delete: { block, day in
                if model.isRepeating(blockID: block.id) {
                    deleteQuestion = ScheduleScopeQuestion(action: .delete, blockID: block.id, day: day)
                } else {
                    model.delete(blockID: block.id, scope: .everyWeek, on: day)
                }
            },
            setOut: { laneID, isOut, day in model.setOut(laneID: laneID, isOut, on: day) },
            addToDay: { laneID, day in sheet = .block(.oneOff(laneID: laneID, day: day)) }
        )
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        HStack(spacing: 4) {
            Button { model.step(-1) } label: {
                Image(systemName: "chevron.left")
                    .accessibilityLabel(model.mode == .week ? "Previous Week" : "Previous Day")
            }
            Button("Today") { model.goToToday() }
                .disabled(model.isToday)
            Button { model.step(1) } label: {
                Image(systemName: "chevron.right")
                    .accessibilityLabel(model.mode == .week ? "Next Week" : "Next Day")
            }
        }
        .buttonStyle(.bordered)
        Picker("View", selection: $model.mode) {
            ForEach(SchedulesPageModel.Mode.allCases) { mode in
                Text(mode.label).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        if model.hasLanes { laneMenu }
        if model.hasLanes { moreMenu }
    }

    /// The lane filter (iPhone's Day view) or the lane the Week view shows.
    @ViewBuilder
    private var laneMenu: some View {
        if model.mode == .week {
            Picker("Lane", selection: Binding(
                get: { model.weekLane?.id }, set: { model.weekLaneID = $0 }
            )) {
                ForEach(model.lanes) { lane in
                    Text(lane.name).tag(Optional(lane.id))
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        } else if isCompact {
            Picker("Lanes", selection: $laneFilter) {
                Text("All Lanes").tag(UUID?.none)
                ForEach(model.lanes) { lane in
                    Text(lane.name).tag(Optional(lane.id))
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("Add Block…", systemImage: "plus") {
                sheet = .block(.new(laneID: nil, weekday: Weekday(date: model.day)))
            }
            Button("Add to This Day…", systemImage: "calendar.badge.plus") {
                sheet = .block(.oneOff(laneID: nil, day: model.day))
            }
            // A block cancelled for the day isn't on it to tap, so it comes back from here.
            ForEach(model.resolved.cancelledBlocks) { block in
                Button(ScheduleText.bringBack(block.values), systemImage: "arrow.uturn.backward") {
                    model.undoChange(blockID: block.id, on: model.day)
                }
            }
            if model.resolved.isChanged {
                Button("Undo This Day’s Changes", systemImage: "arrow.uturn.backward") {
                    model.undoAllChanges(on: model.day)
                }
            }
            Divider()
            Button("Lanes…", systemImage: "rectangle.split.3x1") { sheet = .lanes }
            Button("Add a Person…", systemImage: "person.badge.plus") { askForPerson() }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
        .fixedSize()
    }

    // MARK: - First run

    private var setUpState: some View {
        ContentUnavailableView {
            Label("Set up your schedules", systemImage: "rectangle.split.3x1")
        } description: {
            Text("See our class, the adolescent room and your planned lessons side by side. "
                + "Start with those three lanes, then add your co-teacher.")
        } actions: {
            Button("Set Up Schedules") {
                if model.setUp() { askForPerson() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxHeight: .infinity)
    }

    private func askForPerson() {
        newPersonName = ""
        Task {
            // Let a closing sheet finish before the alert goes up.
            try? await Task.sleep(for: .milliseconds(350))
            showingAddPerson = true
        }
    }

    // MARK: - Warnings

    /// Scrolls to the lesson a warning is about and outlines it for a moment.
    private func showWarning(_ warning: ScheduleDay.Warning) {
        guard let row = ScheduleDayRows.row(holdingLesson: warning.lessonID, in: model.resolved) else { return }
        if isCompact {
            if laneFilter != nil, laneFilter != row.lane.id { laneFilter = nil }
            scrollTarget = row.id
        } else {
            let range = ScheduleGridLayout.range(of: model.resolved)
            let placed = ScheduleGridLayout.place(model.resolved.lane(row.lane.id)?.items ?? [], from: range.lowerBound)
            let top = placed.first { $0.id == row.item.id }?.top
                ?? ScheduleGridLayout.top(of: row.item.startMinute, from: range.lowerBound)
            withAnimation { position.scrollTo(y: max(top - 40, 0)) }
        }
        highlightedRowID = row.id
        Task {
            try? await Task.sleep(for: .seconds(2))
            if highlightedRowID == row.id { highlightedRowID = nil }
            scrollTarget = nil
        }
    }
}
