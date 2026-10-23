import SwiftUI
import CoreData

/// The Schedule tab, which only reads: the header line with previous and
/// next day, a Now card on today, and the day as one list in time order,
/// each row tagged with its lane. The guide's lessons show as "With Danny"
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
        let model = AssistantScheduleModel(
            context: coreDataStack.viewContext,
            guideName: { [bootstrapper] in bootstrapper.guideNameToShow }
        )
        model.load()
        #if DEBUG
        // For screenshots: `-AssistantScheduleLane "Morah Devora"` opens on
        // one lane, and `-AssistantScheduleStep 1` that many school days on.
        if let name = UserDefaults.standard.string(forKey: "AssistantScheduleLane") {
            model.laneFilter = model.laneOptions.first { $0.name == name }?.id
        }
        for _ in 0..<max(0, UserDefaults.standard.integer(forKey: "AssistantScheduleStep")) {
            model.step(forward: true)
        }
        #endif
        self.model = model
        return model
    }

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
    @State private var showingClassroom = false
    /// The time the Now card reads, moved on each minute while the tab shows.
    @State private var clock = Date()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                headerSection
                if model.isToday {
                    nowSection(model.nowCard(at: clock))
                }
                daySection
            }
            .listStyle(.insetGrouped)
            .listSectionSpacing(.compact)
            .contentMargins(.top, 4, for: .scrollContent)
            .navigationTitle("Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .refreshable { model.load() }
        }
        .sheet(isPresented: $showingDatePicker) {
            AssistantDatePickerSheet(date: model.day, earliest: nil) { model.show($0) }
        }
        .sheet(isPresented: $showingClassroom) {
            AssistantClassroomSheet()
        }
        .onAppear { model.load() }
        .task { await followClock() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { clock = Date() }
        }
    }

    /// Moves `clock` on at each minute's turn while the tab is on screen,
    /// so the Now card follows the day. (A `TimelineView` in the list broke
    /// its sections apart.)
    private func followClock() async {
        while !Task.isCancelled {
            clock = Date()
            let second = Calendar.current.component(.second, from: clock)
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
            laneMenu
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
                HStack(spacing: 5) {
                    if model.isToday {
                        Text("Today").font(.headline)
                    }
                    Text(model.day.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(model.isToday ? .subheadline : .headline)
                        .foregroundStyle(model.isToday ? .secondary : .primary)
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

    private var laneMenu: some View {
        Menu {
            Picker("Show", selection: Binding(get: { model.laneFilter }, set: { model.laneFilter = $0 })) {
                Text("Everyone").tag(UUID?.none)
                ForEach(model.laneOptions) { lane in
                    Text(lane.name).tag(UUID?.some(lane.id))
                }
            }
        } label: {
            Label(
                "Show",
                systemImage: model.laneFilter == nil
                    ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill"
            )
            .labelStyle(.iconOnly)
        }
        .disabled(model.laneOptions.isEmpty)
        .accessibilityLabel("Show one lane")
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
                if let filter = model.laneFilter, let lane = model.laneOptions.first(where: { $0.id == filter }) {
                    HStack(spacing: 6) {
                        Image(systemName: "line.3.horizontal.decrease")
                            .accessibilityHidden(true)
                        Text("Only \(lane.name)")
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Button("Show Everyone") { model.laneFilter = nil }
                            .buttonStyle(.borderless)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private func nowSection(_ card: AssistantScheduleRows.NowCard?) -> some View {
        if let card {
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
                    AssistantScheduleRowView(row: row)
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

/// Coming back to the app reads what changed while it was away (imports
/// don't reload the tab while it's off screen), and a tab left on today
/// moves on to the new today. A modifier of its own, so the scene phase's
/// changes redraw only this.
private struct ScheduleFollowsScene: ViewModifier {
    let model: AssistantScheduleModel
    @Environment(\.scenePhase) private var scenePhase
    /// Whether the tab showed today when the app left; nil until it has left.
    @State private var leftOnToday: Bool?

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { oldPhase, phase in
            if phase == .active, oldPhase != .active {
                model.followScene(isActive: true)
                if leftOnToday == true { model.showToday() } else { model.load() }
                leftOnToday = nil
            } else if phase != .active, oldPhase == .active {
                model.followScene(isActive: false)
                leftOnToday = model.isToday
            }
        }
    }
}
