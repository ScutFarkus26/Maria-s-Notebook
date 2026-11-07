import SwiftUI
import CoreData

/// The Schedule tab, which only reads: one schedule at a time, picked at the
/// top (our class, the adolescent room, the guide, Morah Devora), with the
/// header line, previous and next day, a Now card on today, and that
/// schedule's day in time order. The guide's lessons show as "With Danny"
/// rows with the children only, never a lesson's name.
///
/// The model is made the first time the tab shows, and follows imports only
/// while the tab is on screen: coming back to it loads what arrived.
struct AssistantScheduleTab: View {
    let coreDataStack: CoreDataStack

    @Environment(AssistantBootstrapper.self) private var bootstrapper
    @State private var model: AssistantScheduleModel?

    var body: some View {
        Group {
            if let model {
                AssistantScheduleView(model: model)
                    .modifier(ScheduleFollowsScene(model: model))
            } else {
                ProgressView()
            }
        }
        .task {
            let model = model ?? makeModel()
            if let storeID = coreDataStack.sharedPersistentStore?.identifier {
                await model.followRemoteImports(into: storeID)
            }
        }
    }

    private func makeModel() -> AssistantScheduleModel {
        // Not loaded here: the view's `onAppear` loads it, before its first
        // frame. Both used to, back to back (bug hunt 2026-11-03 #27).
        let model = AssistantScheduleModel(
            context: coreDataStack.viewContext,
            guideName: { [bootstrapper] in bootstrapper.guideNameToShow }
        )
        #if DEBUG
        // For screenshots: `-AssistantScheduleLane "Morah Devora"` opens on
        // one lane, and `-AssistantScheduleStep 1` that many school days on.
        if let name = UserDefaults.standard.string(forKey: "AssistantScheduleLane") {
            model.load()
            model.laneFilter = model.laneOptions.first { $0.name == name }?.id
        }
        for _ in 0..<max(0, UserDefaults.standard.integer(forKey: "AssistantScheduleStep")) {
            model.step(forward: true)
        }
        #endif
        self.model = model
        return model
    }

    /// Where the schedule last chosen on this phone is kept, by lane ID.
    static let chosenLaneKey = "Assistant.schedule.chosenLane"

    /// Launched with `-AssistantShowSchedule`: the app opens on this tab
    /// (Debug only), for screenshots.
    static var isRequestedAtLaunch: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-AssistantShowSchedule")
        #else
        false
        #endif
    }
}

struct AssistantScheduleView: View {
    let model: AssistantScheduleModel

    @State private var showingDatePicker = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showingClassroom = false
    @AppStorage(AssistantScheduleTab.chosenLaneKey) private var chosenLane = ""

    var body: some View {
        NavigationStack {
            List {
                headerSection
                if model.isToday {
                    AssistantScheduleNowSection(model: model)
                }
                daySection
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .contentMargins(.top, 4, for: .scrollContent)
            .safeAreaInset(edge: .top, spacing: 0) { laneSwitcher }
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .refreshable { model.load() }
        }
        // Lanes arrive, or the guide removes the one shown: settle on one.
        .onChange(of: model.laneOptions, initial: true) {
            model.settleLane(preferring: UUID(uuidString: chosenLane))
        }
        .sheet(isPresented: $showingDatePicker) {
            AssistantDatePickerSheet(date: model.day, earliest: nil) { model.show($0) }
        }
        .sheet(isPresented: $showingClassroom) {
            AssistantClassroomSheet()
        }
        .onAppear { model.reloadAfterAway() }
        .task { await followClock() }
    }

    /// Moves the model's `clock` on at each minute's turn while the tab is
    /// on screen, so the Now card follows the day. (A `TimelineView` in the
    /// list broke its sections apart.) Only the Now card reads it
    /// (`AssistantScheduleNowSection`): it used to be this view's own state,
    /// and each minute rebuilt every row of the day (bug hunt 2026-11-03 #26).
    /// Past midnight, a tab on today moves to the new today
    /// (`AssistantScheduleModel.minuteTurned`).
    private func followClock() async {
        while !Task.isCancelled {
            model.minuteTurned()
            let second = Calendar.current.component(.second, from: model.clock)
            guard (try? await Task.sleep(for: .seconds(60 - second))) != nil else { return }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if !model.isToday {
                Button("Today") { model.showToday() }
            }
        }
        ToolbarItem(placement: .principal) {
            dayStepper
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingClassroom = true
            } label: {
                Label("Classroom", systemImage: "person.crop.circle")
                    .labelStyle(.iconOnly)
            }
            .accessibilityHint("Your guide, your name, and leaving the classroom")
        }
    }

    private var dayStepper: some View {
        HStack(spacing: 4) {
            Button {
                model.step(forward: false)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous school day")

            Button {
                showingDatePicker = true
            } label: {
                // At accessibility text sizes only the date: "Today" beside
                // it pushed the arrows off (bug hunt 2026-11-06 #17), as on
                // Attendance's header. The Today button shows it's not today.
                let showsToday = model.isToday && !dynamicTypeSize.isAccessibilitySize
                HStack(spacing: 5) {
                    if showsToday {
                        Text("Today").font(.headline)
                    }
                    Text(model.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(showsToday ? .subheadline : .headline)
                        .foregroundStyle(showsToday ? .secondary : .primary)
                }
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.primary)
            }
            .accessibilityLabel(model.day.formatted(date: .complete, time: .omitted))
            .accessibilityHint("Choose another day")

            Button {
                model.step(forward: true)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next school day")
        }
    }

    // MARK: - Switcher

    /// One button per schedule, as wide as its name, in a row that slides
    /// sideways when the names don't fit: equal segments cut "Adolescent
    /// room" short on the iPhone SE. One lane needs no switcher.
    @ViewBuilder
    private var laneSwitcher: some View {
        if model.laneOptions.count > 1 {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(model.laneOptions) { lane in
                            laneButton(lane).id(lane.id)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
                .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                // A schedule chosen past the edge comes into view.
                .onChange(of: model.laneFilter, initial: true) { _, lane in
                    if let lane { proxy.scrollTo(lane, anchor: .center) }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }

    /// Shows that schedule, and remembers it on this phone.
    private func laneButton(_ lane: AssistantScheduleRows.LaneOption) -> some View {
        let isChosen = model.laneFilter == lane.id
        return Button {
            model.laneFilter = lane.id
            chosenLane = lane.id.uuidString
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(isChosen ? Color.white : AssistantScheduleStyle.color(lane.colorRaw, index: lane.index))
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(lane.name)
                    .lineLimit(1)
            }
            .font(.subheadline.weight(isChosen ? .semibold : .regular))
            .foregroundStyle(isChosen ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isChosen ? Color.accentColor : Color(uiColor: .secondarySystemGroupedBackground),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChosen ? .isSelected : [])
        .accessibilityHint("Shows this schedule")
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.headerLine)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if let changed = model.changedLine {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .accessibilityHidden(true)
                        Text(changed)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
                }
                ForEach(model.outLines, id: \.self) { line in
                    Text(line)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var daySection: some View {
        if model.resolved != nil, !model.hasLanes {
            Section {
                ContentUnavailableView(
                    "No Schedule Yet",
                    systemImage: "calendar.day.timeline.left",
                    description: Text(
                        "\(model.guideName) hasn't set up the class schedule yet. It shows here once it's ready."
                    )
                )
            }
        } else if let dayOff = model.dayOff {
            Section {
                ContentUnavailableView(
                    "No School",
                    systemImage: "sun.max",
                    description: Text(Self.dayOffText(dayOff))
                )
            }
        } else {
            let rows = model.rows
            Section {
                if rows.isEmpty, model.resolved != nil {
                    Text(emptyDayText)
                        .foregroundStyle(.secondary)
                }
                ForEach(rows) { row in
                    AssistantScheduleRowView(row: row, showsLane: model.laneFilter == nil)
                }
            }
        }
    }

    private var emptyDayText: String {
        guard let filter = model.laneFilter, let lane = model.laneOptions.first(where: { $0.id == filter }) else {
            return "Nothing on the schedule this day."
        }
        return "Nothing for \(lane.name) this day."
    }

    private static func dayOffText(_ dayOff: AssistantAttendanceViewModel.DayOff) -> String {
        switch dayOff {
        case .weekend: "There's no school this day."
        case .holiday(let reason?): "There's no school this day: \(reason)."
        case .holiday(nil): "There's no school this day."
        }
    }
}

/// The Now card's section: the one part of the tab that reads the time, so
/// the minute's clock redraws it alone.
private struct AssistantScheduleNowSection: View {
    let model: AssistantScheduleModel

    var body: some View {
        if let card = model.nowCard(at: model.clock) {
            Section("Now") {
                switch card {
                case .beforeSchool:
                    Text("The day hasn't started yet.")
                        .foregroundStyle(.secondary)
                case .afterSchool:
                    Text("The day's schedule is over.")
                        .foregroundStyle(.secondary)
                case .lines(let lines):
                    ForEach(lines) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle()
                                .fill(AssistantScheduleStyle.color(line.laneColorRaw, index: line.laneIndex))
                                .frame(width: 9, height: 9)
                                .accessibilityHidden(true)
                            Text(line.text)
                                .font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }
}

/// Coming back to the app reads what changed while it was away (imports
/// don't reload the tab while it's off screen), after a night away goes to
/// today (`AssistantScheduleModel.reloadAfterAway`), and the Now card reads
/// the time again. A modifier of its own, so the scene phase's changes
/// redraw only this: the tab's view read the phase too until 2026-11-03 (#26).
private struct ScheduleFollowsScene: ViewModifier {
    let model: AssistantScheduleModel
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { oldPhase, phase in
            if phase == .active, oldPhase != .active {
                // The Now card reads the time now, not the minute it left.
                model.clock = model.now()
                model.followScene(isActive: true)
                model.reloadAfterAway()
            } else if phase != .active, oldPhase == .active {
                model.followScene(isActive: false)
            }
        }
    }
}
