import SwiftUI
import CoreData

/// The whole app, once you've joined: one day's class, one tile each.
///
/// During arrival a tap marks a child present. **Close Arrival** asks, naming
/// them, before marking everyone still unmarked absent; after that a tap marks
/// tardy. Every mark made on its own day carries its time.
///
/// The day's count sits above the grid (`AssistantClassCount`); the arrival
/// control and the iCloud line in the bottom bar (`AssistantArrivalBar`), in
/// thumb reach. On a phone, three columns of
/// one-line tiles fit a class of 22 on an SE: on a phone with a home button
/// the status bar steps aside and the top bar shows its own clock, which gives
/// the grid those 20 points, and its tiles and gaps shrink a little (to 46
/// and 6 points) so eight rows fit above iOS 26's taller bottom bar. A taller
/// phone (a Pro Max, say) grows the tiles to fill its screen instead of
/// leaving the space under the grid empty. Anything longer scrolls, with a
/// fade above the bar, and closing arrival asks first either way.
///
/// It opens on today. The ‹ › arrows, or a sideways swipe on the grid, step
/// through school days (skipping weekends and the guide's days off), tapping
/// the date opens a picker for any day, past or future, and Today comes back.
/// A day the guide has locked shows a lock and read-only rows;
/// `CDAttendanceStore` refuses edits to it anyway.
///
/// The small pleasures: the grid sits on the background she chose (Sky, the
/// default, tints today with the color of the sky at this hour), and turns
/// faintly amber once arrival closes; a mark bounces and its green spreads
/// from her finger; a birthday child has a cake and sparkles; a child back
/// after days away has a wave; the header counts the school day, with a party
/// on the first and the hundredth; when everyone's marked a ripple runs
/// across the grid (and on day 100, confetti); and if she turns them on, the
/// Montessori bells climb the scale as the class fills. None of it moves a
/// tile or waits to be dismissed.
struct AssistantAttendanceView: View {
    let coreDataStack: CoreDataStack
    @Environment(AssistantBootstrapper.self) private var bootstrapper

    @State var viewModel: AssistantAttendanceViewModel?
    @State var showingClassroom = false
    @State var showingDatePicker = false
    @State private var noteRow: AssistantAttendanceViewModel.Row?
    /// The day on screen when the note sheet opened: the note goes there,
    /// even if the grid moves on meanwhile (a tapped reminder, the morning).
    @State private var noteDay: Date?
    /// The child whose pickup time is being set (Leaving Early…).
    @State private var pickupRow: AssistantAttendanceViewModel.Row?
    /// The "Marked 3 absent · Undo" line after closing arrival. It stays
    /// until the next mark, a phase or day change, or the app leaving the
    /// foreground.
    @State private var lateUndo: ArrivalUndo?
    /// Which way the last step through days went, so the grid slides that way.
    @State var stepEdge: Edge = .trailing
    /// Bumped when everyone's marked, for the ripple across the grid.
    @State var ripples = 0
    /// Bumped when everyone's marked on the hundredth day.
    @State var confettiBursts = 0
    /// Bumped by the bar's Email the Front Desk (`AssistantFrontDeskMail`).
    @State private var frontDeskRequests = 0
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// The top safe area outside the navigation bar: 20 on a phone with a
    /// home button (the SE), 0 once its status bar is hidden, 44 or more
    /// beside a notch or Dynamic Island, 24 on an iPad.
    @State private var topInset: CGFloat = 0
    /// The grid's room inside the scroll view, between the bars and inside
    /// its padding, for sizing phone tiles to the screen.
    @State private var gridSpace: CGSize = .zero
    /// The locked-day and error lines above the grid, while shown.
    @State private var noticesHeight: CGFloat = 0
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    /// The count line's own height: taller than `classTotalHeight` at large
    /// text sizes.
    @State private var classTotalMeasured = AssistantAttendanceView.classTotalHeight
    @AppStorage(AssistantWallpaper.key) private var wallpaperRaw = AssistantWallpaper.standard.rawValue
    /// Alphabetical across the rows or down the columns.
    @AppStorage(AssistantGridOrder.key) private var gridOrderRaw = AssistantGridOrder.across.rawValue
    /// One block per level, each with its heading (`AssistantLevelGroups`).
    @AppStorage(AssistantLevelGroups.key) private var groupsByLevel = false

    /// Sky or Plain: tiles as they are. Anything else frosts them.
    private var backdropIsQuiet: Bool { AssistantWallpaper.resolved(wallpaperRaw).isQuiet }

    private static let phoneColumnWidth: CGFloat = 105
    private var gridSpacing: CGFloat { usesShortNames ? Self.phoneGridSpacing(isSE: hidesStatusBar) : 10 }

    /// Phones: three columns of short names. Wider screens have room for
    /// full names.
    private var usesShortNames: Bool { horizontalSizeClass == .compact }

    /// Only a home-button phone: beside a notch the status bar has its own
    /// strip that the grid couldn't use anyway.
    var hidesStatusBar: Bool { usesShortNames && topInset <= 20 }

    /// Three (or more) adaptive columns; two at accessibility text sizes,
    /// where three would cut the time off every tile.
    private var gridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
        }
        return [GridItem(.adaptive(minimum: usesShortNames ? Self.phoneColumnWidth : 150), spacing: gridSpacing)]
    }

    /// How many columns the grid lays out: the adaptive grid's own count for
    /// its width, or two at accessibility text sizes.
    private var gridColumnCount: Int {
        if dynamicTypeSize.isAccessibilitySize { return 2 }
        let columnWidth = usesShortNames ? Self.phoneColumnWidth : 150
        return max(1, Int((gridSpace.width + gridSpacing) / (columnWidth + gridSpacing)))
    }

    /// `rows` in the order the grid shows them. Down waits for the grid's
    /// width, so it never arranges for one column.
    private func arranged(_ rows: [AssistantAttendanceViewModel.Row]) -> [AssistantAttendanceViewModel.Row] {
        guard gridSpace.width > 0 else { return rows }
        return AssistantGridOrder.resolved(gridOrderRaw).arranged(rows, columns: gridColumnCount)
    }

    /// The level blocks, when Group by Level is on and the class has more
    /// than one level; otherwise empty, and the grid is one block.
    private func levelGroups(
        _ viewModel: AssistantAttendanceViewModel
    ) -> [AttendanceLevelGroups.Group<AssistantAttendanceViewModel.Row>] {
        guard groupsByLevel else { return [] }
        let groups = AttendanceLevelGroups.grouped(viewModel.rows, level: \.level)
        return groups.count > 1 ? groups : []
    }

    /// A level heading, slimmer on a phone so the class still fits.
    private var levelHeaderHeight: CGFloat { usesShortNames ? Self.phoneLevelHeaderHeight : 26 }
    private var levelHeaderSpacing: CGFloat { usesShortNames ? Self.phoneLevelHeaderSpacing : 6 }

    /// How many lines of tiles the grid takes: each level block starts its
    /// own line.
    private func tileLines(_ viewModel: AssistantAttendanceViewModel, columns: Int) -> Int {
        let groups = levelGroups(viewModel)
        let counts = groups.isEmpty ? [viewModel.rows.count] : groups.map(\.items.count)
        return counts.reduce(0) { $0 + ($1 + columns - 1) / columns }
    }

    /// Phone tiles sized to the screen, below any notices and the count.
    private func phoneTileHeight(_ viewModel: AssistantAttendanceViewModel) -> CGFloat {
        guard usesShortNames, !dynamicTypeSize.isAccessibilitySize else { return AttendanceTile.phoneHeight }
        let columns = gridColumnCount
        let notices = (AssistantDayNotices.shows(for: viewModel) ? noticesHeight + 12 : 0)
            + classTotalMeasured + Self.classTotalSpacing
        return Self.phoneTileHeight(
            gridHeight: gridSpace.height - notices,
            columns: columns,
            lines: tileLines(viewModel, columns: columns),
            levelBlocks: levelGroups(viewModel).count,
            isSE: hidesStatusBar
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    content(viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Attendance")
            .toolbarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            // A picture behind the date would make it hard to read.
            .toolbarBackground(backdropIsQuiet ? .automatic : .visible, for: .navigationBar)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    // Room for the grid's fade (`fadeAboveBar`): tiles
                    // scrolled toward the bar fade out here rather than sit
                    // half-visible against it.
                    Color.clear
                        .frame(height: Self.barFadeHeight)
                        .allowsHitTesting(false)
                    if let viewModel {
                        AssistantArrivalBar(
                            viewModel: viewModel, coreDataStack: coreDataStack, undo: $lateUndo,
                            onEmailFrontDesk: { frontDeskRequests += 1 }
                        )
                    }
                }
            }
        }
        .environment(\.attendanceBackdropIsQuiet, backdropIsQuiet)
        .statusBarHidden(hidesStatusBar)
        .sensoryFeedback(.success, trigger: viewModel?.completions) {
            AssistantAttendanceViewModel.isCompletion(from: $0, to: $1)
        }
        .onChange(of: viewModel?.completions) { old, new in
            guard AssistantAttendanceViewModel.isCompletion(from: old, to: new) else { return }
            celebrateEveryoneMarked()
        }
        .overlay { HundredthDayConfetti(trigger: confettiBursts) }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .modifier(AssistantFirstRunPrompts())
        .sheet(isPresented: $showingClassroom) {
            AssistantClassroomSheet()
        }
        .sheet(isPresented: $showingDatePicker) {
            if let viewModel {
                AssistantDatePickerSheet(date: viewModel.date, earliest: viewModel.earliestDay) { picked in
                    viewModel.load(picked)
                }
            }
        }
        .sheet(item: $noteRow) { row in
            AttendanceNoteSheet(
                studentName: row.name,
                initialText: row.note,
                sharedWith: "Your guide sees this note too.",
                onSave: { viewModel?.setNote($0, for: row, on: noteDay) }
            )
        }
        .modifier(AssistantPickupSheet(row: $pickupRow, viewModel: viewModel))
        .task {
            // Every time the screen comes back (another tab, say), not just
            // the first: SwiftUI ends this task while it's away, so imports
            // in between were never shown.
            if let viewModel { viewModel.load() } else { startDay() }
            // The class, the guide's marks and locked days all arrive by
            // import; without this the screen shows them only when reloaded.
            if let viewModel, let storeID = coreDataStack.sharedPersistentStore?.identifier {
                await viewModel.followRemoteImports(into: storeID)
            }
        }
        .modifier(ArrivalReminderFollower(viewModel: viewModel, context: coreDataStack.viewContext))
        .modifier(AssistantFrontDeskMail(viewModel: viewModel, requests: frontDeskRequests))
        .onReceive(NotificationCenter.default.publisher(for: .attendanceChangedBySiri)) { _ in
            // A mark made with Siri while the screen was open.
            viewModel?.load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .assistantShowToday)) { _ in
            viewModel?.load(Date())
        }
        .onChange(of: viewModel?.date) {
            // Undo belongs to the day it was offered on.
            lateUndo = nil
        }
        .onChange(of: noteRow?.id) { _, editing in
            noteDay = editing == nil ? nil : viewModel?.date
            viewModel?.pauseRemoteReloads(editing != nil)
        }
        .modifier(AssistantReloadOnReturn(viewModel: viewModel) {
            // The undo line goes when the app leaves the foreground.
            if lateUndo != nil { lateUndo = nil }
        })
    }

    // MARK: - Content

    private func startDay() {
        // The sample's marks go into no share, and its Late phase is kept
        // apart from the real class's.
        let isSample = AssistantSampleClass.isActive
        let model = AssistantAttendanceViewModel(
            context: coreDataStack.viewContext,
            container: isSample ? nil : coreDataStack.container,
            defaults: isSample ? AssistantSampleClass.defaults : .standard
        )
        model.load()
        viewModel = model
    }

    @ViewBuilder
    private func content(_ viewModel: AssistantAttendanceViewModel) -> some View {
        if let dayOff = viewModel.dayOff {
            AssistantDayOffView(dayOff: dayOff, isToday: viewModel.isToday) { viewModel.load() }
                .background { AssistantBackdrop(isToday: viewModel.isToday, isLate: false, date: viewModel.date) }
        } else if viewModel.rows.isEmpty, bootstrapper.removedFromClass {
            AssistantRemovedFromClassView()
        } else if viewModel.rows.isEmpty {
            ContentUnavailableView {
                Label("No students yet", systemImage: "person.3")
            } description: {
                Text("The class list comes down from iCloud. It can take a minute after you join.")
            } actions: {
                Button("Check Again") { viewModel.load() }
            }
        } else {
            let tileHeight = phoneTileHeight(viewModel)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Only while shown: an empty one still took the spacing.
                    if AssistantDayNotices.shows(for: viewModel) {
                        AssistantDayNotices(viewModel: viewModel)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { noticesHeight = $0 }
                    }
                    VStack(alignment: .leading, spacing: Self.classTotalSpacing) {
                        classTotal(viewModel)
                        grid(viewModel, tileHeight: tileHeight)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 2)
                .padding(.bottom, 12)
                .id(viewModel.date)
                .transition(.push(from: stepEdge))
            }
            .onGeometryChange(for: CGSize.self) { proxy in
                // The scroll view already sits between the bars; less the
                // grid's padding: 16 each side, 2 above, 12 below.
                CGSize(width: proxy.size.width - 32, height: proxy.size.height - 14)
            } action: { gridSpace = $0 }
            .mask { fadeAboveBar }
            .background {
                AssistantBackdrop(
                    isToday: viewModel.isToday,
                    isLate: showsLate(viewModel),
                    date: viewModel.date,
                    hereFraction: viewModel.hereFraction
                )
            }
            .refreshable { viewModel.load() }
            .simultaneousGesture(daySwipe(viewModel))
        }
    }

    static let classTotalHeight: CGFloat = 20
    static let classTotalSpacing: CGFloat = 8

    /// "17 of 22 here", above the grid in the room the top padding had. It
    /// grows with large text rather than spill onto the tiles. On an SE on
    /// another day, where the Today button takes the top bar's clock, the
    /// time sits at its end (under it at accessibility text sizes, where
    /// beside it would cut the count to "0…").
    private func classTotal(_ viewModel: AssistantAttendanceViewModel) -> some View {
        let showsClock = hidesStatusBar && !viewModel.isToday
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 10))
        return layout {
            AssistantClassCount(rows: viewModel.rows, isFuture: viewModel.isFuture)
            if showsClock {
                AssistantCountClock()
            }
        }
        .frame(minHeight: Self.classTotalHeight)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { classTotalMeasured = $0 }
        .modifier(AssistantGridLabelStyle(isCompact: usesShortNames))
    }

    /// One block of tiles, or one per level with its heading.
    @ViewBuilder
    private func grid(_ viewModel: AssistantAttendanceViewModel, tileHeight: CGFloat) -> some View {
        let groups = levelGroups(viewModel)
        if groups.isEmpty {
            tileGrid(arranged(viewModel.rows), viewModel: viewModel, height: tileHeight, firstIndex: 0)
        } else {
            // Where each block's ripple starts: after the lines above it.
            let columns = gridColumnCount
            let starts = groups.reduce(into: [0]) { starts, group in
                starts.append(starts.last! + (group.items.count + columns - 1) / columns * columns)
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(groups.enumerated()), id: \.element.level) { position, group in
                    VStack(alignment: .leading, spacing: levelHeaderSpacing) {
                        AssistantLevelHeader(
                            level: group.level, rows: group.items, isFuture: viewModel.isFuture,
                            height: levelHeaderHeight, isCompact: usesShortNames
                        )
                        tileGrid(
                            arranged(group.items), viewModel: viewModel, height: tileHeight,
                            firstIndex: starts[position]
                        )
                    }
                }
            }
        }
    }

    private func tileGrid(
        _ rows: [AssistantAttendanceViewModel.Row],
        viewModel: AssistantAttendanceViewModel,
        height: CGFloat,
        firstIndex: Int
    ) -> some View {
        LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                tile(row, viewModel: viewModel, height: height, index: firstIndex + index)
            }
        }
    }

    /// A new mark retires the Undo for the last Close Arrival.
    private func tile(
        _ row: AssistantAttendanceViewModel.Row,
        viewModel: AssistantAttendanceViewModel,
        height: CGFloat,
        index: Int
    ) -> some View {
        AttendanceTile(
            row: row,
            tapTarget: viewModel.statusAfterTap(for: row),
            tapHint: viewModel.isFuture ? "Only absences ahead" : "Hold to change",
            menuStatuses: viewModel.menuStatuses,
            canMark: viewModel.canMark,
            usesShortName: usesShortNames,
            height: height,
            onTap: {
                lateUndo = nil
                viewModel.tap(row)
                ring(for: row, in: viewModel)
            },
            markedBy: AssistantAttendanceViewModel.markerName(
                for: row,
                myRecordName: ClassroomIdentity.currentUserRecordName,
                myName: ClassroomIdentity.displayName,
                guideName: bootstrapper.guideName
            ),
            onSetStatus: {
                lateUndo = nil
                viewModel.setStatus($0, for: row)
                ring(for: row, in: viewModel)
            },
            onMarkAbsent: { reason in
                lateUndo = nil
                viewModel.markAbsent(reason: reason, for: row)
                ring(for: row, in: viewModel)
                // "Other" is only as good as the note that says what.
                if reason == .other { noteRow = row }
            },
            onNote: { noteRow = row },
            onPickup: viewModel.allowsPickup(for: row) ? { pickupRow = row } : nil,
            onBack: viewModel.canMark && AttendanceRules.allowsBack(for: row) ? {
                lateUndo = nil
                viewModel.markBack(row)
                ring(for: row, in: viewModel)
            } : nil,
            rippleTrigger: ripples,
            rippleDelay: rippleDelay(at: index)
        )
    }

    /// Late tints the grid only on a day that has arrived.
    private func showsLate(_ viewModel: AssistantAttendanceViewModel) -> Bool {
        viewModel.phase == .late && !viewModel.isFuture
    }

    /// The ripple runs row by row, and left to right within a row.
    private func rippleDelay(at index: Int) -> Double {
        let columns = gridColumnCount
        return Double(index / columns) * 0.07 + Double(index % columns) * 0.035
    }
}

// MARK: - Phone tile sizing

extension AssistantAttendanceView {

    /// The gap between phone tiles: a little tighter on an SE, so eight rows
    /// fit.
    static func phoneGridSpacing(isSE: Bool) -> CGFloat { isSE ? 6 : 8 }

    static let phoneLevelHeaderHeight: CGFloat = 20
    static let phoneLevelHeaderSpacing: CGFloat = 4
    /// How far phone tiles may shrink to make room for the level headings:
    /// still a full tap target.
    static let smallestGroupedTileHeight: CGFloat = 44
    /// How far an SE's tiles may shrink so a class of 22 fits ungrouped:
    /// eight rows of 46 with 6-point gaps are 410 of the about 413 points
    /// between the count and iOS 26's bottom bar. Only the SE's: the
    /// notebook's iPhone grid keeps `AttendanceTile.phoneHeight`.
    static let smallestSETileHeight: CGFloat = 46

    /// A phone tile's height for `lines` lines of tiles in `gridHeight`
    /// (the room below the count). Any phone but the SE fills the room it
    /// has. The SE never grows past its usual size, and shrinks to
    /// `smallestSETileHeight` so 22 fit. Grouped by level, any phone may
    /// shrink to `smallestGroupedTileHeight` so the headings don't push
    /// children out of sight.
    static func phoneTileHeight(
        gridHeight: CGFloat,
        columns: Int,
        lines: Int,
        levelBlocks: Int,
        isSE: Bool
    ) -> CGFloat {
        let spacing = phoneGridSpacing(isSE: isSE)
        let blocks = CGFloat(levelBlocks)
        // Each block's heading, and the wider gap between blocks.
        let headings = blocks == 0 ? 0
            : blocks * (phoneLevelHeaderHeight + phoneLevelHeaderSpacing) + (blocks - 1) * (12 - spacing)
        let minimum = levelBlocks > 0 ? smallestGroupedTileHeight
            : isSE ? smallestSETileHeight : AttendanceTile.phoneHeight
        let height = AttendanceTile.fittedPhoneHeight(
            visibleHeight: gridHeight - headings,
            columns: columns,
            count: lines * columns,
            spacing: spacing,
            minimum: minimum
        )
        return isSE ? min(height, AttendanceTile.phoneHeight) : height
    }
}

// MARK: - Celebrations, bells and the fade

extension AssistantAttendanceView {

    static let barFadeHeight: CGFloat = 14

    /// The grid's mask: whole down to the clear strip above the bottom bar,
    /// fading out across it, and gone under the bar. A mask rather than a
    /// strip painted over the tiles, so they fade into whatever background is
    /// behind them.
    var fadeAboveBar: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: Self.barFadeHeight)
                Color.clear
                    .frame(height: max(proxy.safeAreaInsets.bottom - Self.barFadeHeight, 0))
            }
            .ignoresSafeArea()
        }
    }

    /// Everyone's marked: the ripple and the tune, and on the hundredth day
    /// (today) the confetti and the longer tune.
    func celebrateEveryoneMarked() {
        ripples += 1
        if let viewModel, viewModel.isToday, viewModel.milestone == .hundredthDay {
            confettiBursts += 1
            AttendanceBells.shared.play(.hundredthDay)
        } else {
            AttendanceBells.shared.play(.everyoneMarked)
        }
    }

    /// Her mark's bell, if she has them on: the next note up for a child
    /// here, a low one for an absence, nothing for clearing.
    func ring(for row: AssistantAttendanceViewModel.Row, in viewModel: AssistantAttendanceViewModel) {
        guard AttendanceBells.isOn, let marked = viewModel.rows.first(where: { $0.id == row.id }) else { return }
        switch TileTapMotion.Kind(marked.status) {
        case .here:
            let here = viewModel.rows.count { [.present, .tardy, .leftEarly].contains($0.status) }
            AttendanceBells.shared.play(.here(count: here))
        case .away:
            AttendanceBells.shared.play(.away)
        case .cleared:
            break
        }
    }
}
