import SwiftUI
import CoreData

/// The whole app, once you've joined: one day's class, one tile each.
///
/// During arrival a tap marks a child present. **Close Arrival…** asks, naming
/// them, before marking everyone still unmarked absent; after that a tap marks
/// tardy. Every mark made on its own day carries its time.
///
/// The count, the arrival control and the iCloud line sit in the bottom bar
/// (`AssistantArrivalBar`), in thumb reach. On a phone, three columns of
/// one-line tiles fit a class of 22 on an SE: on a phone with a home button
/// the status bar steps aside and the top bar shows its own clock, which gives
/// the grid those 20 points. A taller phone (a Pro Max, say) grows the tiles
/// to fill its screen instead of leaving the space under the grid empty.
/// Anything longer scrolls, with a fade above the bar, and closing arrival
/// asks first either way.
///
/// It opens on today. The ‹ › arrows, or a sideways swipe on the grid, step
/// through school days (skipping weekends and the guide's days off), tapping
/// the date opens a picker for any day, past or future, and Today comes back.
/// A day the guide has locked shows a lock and read-only rows;
/// `CDAttendanceStore` refuses edits to it anyway.
///
/// The small pleasures: today's grid sits under the color of the sky at this
/// hour, and turns faintly amber once arrival closes; a mark bounces and its
/// green spreads from her finger; a birthday child has a cake and sparkles;
/// when everyone's marked a ripple runs across the grid; and if she turns
/// them on, soft bells climb the scale as the class fills. None of it moves a
/// tile or waits to be dismissed.
struct AssistantAttendanceView: View {
    let coreDataStack: CoreDataStack
    @Environment(AssistantBootstrapper.self) private var bootstrapper

    @State var viewModel: AssistantAttendanceViewModel?
    @State private var showingNameSheet = false
    @State var showingClassroom = false
    @State var showingDatePicker = false
    @State private var noteRow: AssistantAttendanceViewModel.Row?
    /// The "Marked 3 absent · Undo" line after closing arrival. It stays
    /// until the next mark, a phase or day change, or the app leaving the
    /// foreground.
    @State private var lateUndo: ArrivalUndo?
    /// Which way the last step through days went, so the grid slides that way.
    @State var stepEdge: Edge = .trailing
    /// Bumped when everyone's marked, for the ripple across the grid.
    @State private var ripples = 0
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private static let phoneColumnWidth: CGFloat = 105
    private var gridSpacing: CGFloat { usesShortNames ? 8 : 10 }

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

    /// The SE keeps its fixed tiles; any other phone fills the room it has.
    private func phoneTileHeight(_ viewModel: AssistantAttendanceViewModel) -> CGFloat {
        guard usesShortNames, !hidesStatusBar, !dynamicTypeSize.isAccessibilitySize else {
            return AssistantAttendanceTile.phoneHeight
        }
        let columns = max(1, Int((gridSpace.width + gridSpacing) / (Self.phoneColumnWidth + gridSpacing)))
        let notices = AssistantDayNotices.shows(for: viewModel) ? noticesHeight + 12 : 0
        return AssistantAttendanceTile.fittedPhoneHeight(
            visibleHeight: gridSpace.height - notices,
            columns: columns,
            count: viewModel.rows.count,
            spacing: gridSpacing
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 0) {
                    // Tiles scrolled under the bar fade out rather than sit
                    // half-visible against it.
                    AssistantBackdrop.base(isLate: viewModel.map(showsLate) ?? false)
                        .mask(LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom))
                        .frame(height: 14)
                        .allowsHitTesting(false)
                    if let viewModel {
                        AssistantArrivalBar(viewModel: viewModel, coreDataStack: coreDataStack, undo: $lateUndo)
                    }
                }
            }
        }
        .statusBarHidden(hidesStatusBar)
        .sensoryFeedback(.success, trigger: viewModel?.completions)
        .onChange(of: viewModel?.completions) {
            ripples += 1
            AssistantBells.shared.play(.everyoneMarked)
        }
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.top } action: { topInset = $0 }
        .sheet(isPresented: $showingNameSheet) {
            AssistantNameSheet(isRequired: true)
        }
        .sheet(isPresented: $showingClassroom) {
            AssistantClassroomSheet()
        }
        .sheet(isPresented: $showingDatePicker) {
            if let viewModel {
                AssistantDatePickerSheet(date: viewModel.date) { picked in
                    viewModel.load(picked)
                }
            }
        }
        .sheet(item: $noteRow) { row in
            AttendanceNoteSheet(
                studentName: row.name,
                initialText: row.note,
                sharedWith: "Your guide sees this note too.",
                onSave: { viewModel?.setNote($0, for: row) }
            )
        }
        .task {
            // Ask once, on the first run after joining, rather than letting a
            // term's marks accumulate under no name at all.
            if asksForName { showingNameSheet = true }
            if viewModel == nil { startDay() }
            // The class, the guide's marks and locked days all arrive by
            // import; without this the screen shows them only when reloaded.
            if let viewModel, let storeID = coreDataStack.sharedPersistentStore?.identifier {
                await viewModel.followRemoteImports(into: storeID)
            }
        }
        .modifier(ArrivalReminderFollower(viewModel: viewModel, context: coreDataStack.viewContext))
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
            viewModel?.pauseRemoteReloads(editing != nil)
        }
        .modifier(AssistantReloadOnReturn(viewModel: viewModel) {
            // The undo line goes when the app leaves the foreground.
            if lateUndo != nil { lateUndo = nil }
        })
    }

    /// The sample class marks under no one's name, so it doesn't ask.
    private var asksForName: Bool {
        #if DEBUG
        if AssistantSampleClass.isRequested { return false }
        #endif
        return ClassroomIdentity.displayName == nil
    }

    // MARK: - Content

    private func startDay() {
        let model = AssistantAttendanceViewModel(
            context: coreDataStack.viewContext, container: coreDataStack.container
        )
        model.load()
        viewModel = model
    }

    @ViewBuilder
    private func content(_ viewModel: AssistantAttendanceViewModel) -> some View {
        if let dayOff = viewModel.dayOff {
            AssistantDayOffView(dayOff: dayOff, isToday: viewModel.isToday) { viewModel.load() }
                .background { AssistantBackdrop(isToday: viewModel.isToday, isLate: false) }
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
                    AssistantDayNotices(viewModel: viewModel)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { noticesHeight = $0 }
                    LazyVGrid(columns: gridColumns, spacing: gridSpacing) {
                        ForEach(Array(viewModel.rows.enumerated()), id: \.element.id) { index, row in
                            tile(row, viewModel: viewModel, height: tileHeight, index: index)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .id(viewModel.date)
                .transition(.push(from: stepEdge))
            }
            .onGeometryChange(for: CGSize.self) { proxy in
                // The scroll view already sits between the bars; less the
                // grid's padding: 16 each side, 8 above, 12 below.
                CGSize(width: proxy.size.width - 32, height: proxy.size.height - 20)
            } action: { gridSpace = $0 }
            .background { AssistantBackdrop(isToday: viewModel.isToday, isLate: showsLate(viewModel)) }
            .refreshable { viewModel.load() }
            .simultaneousGesture(daySwipe(viewModel))
        }
    }

    /// A new mark retires the Undo for the last switch to Late.
    private func tile(
        _ row: AssistantAttendanceViewModel.Row,
        viewModel: AssistantAttendanceViewModel,
        height: CGFloat,
        index: Int
    ) -> some View {
        AssistantAttendanceTile(
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
        let columnWidth = usesShortNames ? Self.phoneColumnWidth : 150
        let columns = dynamicTypeSize.isAccessibilitySize
            ? 2
            : max(1, Int((gridSpace.width + gridSpacing) / (columnWidth + gridSpacing)))
        return Double(index / columns) * 0.07 + Double(index % columns) * 0.035
    }

    /// Her mark's bell, if she has them on: the next note up for a child
    /// here, a low one for an absence, nothing for clearing.
    private func ring(for row: AssistantAttendanceViewModel.Row, in viewModel: AssistantAttendanceViewModel) {
        guard AssistantBells.isOn, let marked = viewModel.rows.first(where: { $0.id == row.id }) else { return }
        switch TileTapMotion.Kind(marked.status) {
        case .here:
            let here = viewModel.rows.count { [.present, .tardy, .leftEarly].contains($0.status) }
            AssistantBells.shared.play(.here(count: here))
        case .away:
            AssistantBells.shared.play(.away)
        case .cleared:
            break
        }
    }

}
