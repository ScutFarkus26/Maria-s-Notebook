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
/// the grid those 20 points. Anything longer scrolls, with a fade above the
/// bar, and closing arrival asks first either way.
///
/// It opens on today. The ‹ › arrows, or a sideways swipe on the grid, step
/// through school days (skipping weekends and the guide's days off), tapping
/// the date opens a picker for any day, past or future, and Today comes back.
/// A day the guide has locked shows a lock and read-only rows;
/// `CDAttendanceStore` refuses edits to it anyway.
struct AssistantAttendanceView: View {
    let coreDataStack: CoreDataStack
    @Environment(AssistantBootstrapper.self) private var bootstrapper

    @State private var viewModel: AssistantAttendanceViewModel?
    @State private var showingNameSheet = false
    @State private var showingClassroom = false
    @State private var showingDatePicker = false
    @State private var noteRow: AssistantAttendanceViewModel.Row?
    /// The "Marked 3 absent · Undo" line after closing arrival. It stays
    /// until the next mark, a phase or day change, or the app leaving the
    /// foreground.
    @State private var lateUndo: ArrivalUndo?
    /// Which way the last step through days went, so the grid slides that way.
    @State private var stepEdge: Edge = .trailing
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    /// The top safe area outside the navigation bar: 20 on a phone with a
    /// home button (the SE), 0 once its status bar is hidden, 44 or more
    /// beside a notch or Dynamic Island, 24 on an iPad.
    @State private var topInset: CGFloat = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Phones: three columns of short names. Wider screens have room for
    /// full names.
    private var usesShortNames: Bool { horizontalSizeClass == .compact }

    /// Only a home-button phone: beside a notch the status bar has its own
    /// strip that the grid couldn't use anyway.
    private var hidesStatusBar: Bool { usesShortNames && topInset <= 20 }

    /// Three (or more) adaptive columns; two at accessibility text sizes,
    /// where three would cut the time off every tile.
    private var gridColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
        }
        return [GridItem(.adaptive(minimum: usesShortNames ? 105 : 150), spacing: usesShortNames ? 8 : 10)]
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
                    LinearGradient(
                        colors: [Color(.systemGroupedBackground).opacity(0), Color(.systemGroupedBackground)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 14)
                    .allowsHitTesting(false)
                    if let viewModel {
                        AssistantArrivalBar(viewModel: viewModel, coreDataStack: coreDataStack, undo: $lateUndo)
                    }
                }
            }
        }
        .statusBarHidden(hidesStatusBar)
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
            ContentUnavailableView {
                Label("No School", systemImage: "sun.max")
            } description: {
                Text(AssistantAttendanceViewModel.dayOffText(dayOff, isToday: viewModel.isToday))
            } actions: {
                Button("Check Again") { viewModel.load() }
            }
        } else if viewModel.rows.isEmpty {
            ContentUnavailableView {
                Label("No students yet", systemImage: "person.3")
            } description: {
                Text("The class list comes down from iCloud. It can take a minute after you join.")
            } actions: {
                Button("Check Again") { viewModel.load() }
            }
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    notices(viewModel)
                    LazyVGrid(columns: gridColumns, spacing: usesShortNames ? 8 : 10) {
                        ForEach(viewModel.rows) { row in
                            tile(row, viewModel: viewModel)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .id(viewModel.date)
                .transition(.push(from: stepEdge))
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { viewModel.load() }
            .simultaneousGesture(daySwipe(viewModel))
        }
    }

    /// A new mark retires the Undo for the last switch to Late.
    private func tile(_ row: AssistantAttendanceViewModel.Row, viewModel: AssistantAttendanceViewModel) -> some View {
        AssistantAttendanceTile(
            row: row,
            tapTarget: viewModel.statusAfterTap(for: row),
            tapHint: viewModel.isFuture ? "Only absences ahead" : "Hold to change",
            menuStatuses: viewModel.menuStatuses,
            canMark: viewModel.canMark,
            usesShortName: usesShortNames,
            onTap: {
                lateUndo = nil
                viewModel.tap(row)
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
            },
            onMarkAbsent: { reason in
                lateUndo = nil
                viewModel.markAbsent(reason: reason, for: row)
                // "Other" is only as good as the note that says what.
                if reason == .other { noteRow = row }
            },
            onNote: { noteRow = row }
        )
    }

}

// MARK: - Toolbar, stepping and notices

extension AssistantAttendanceView {

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if let viewModel, !viewModel.isToday {
                Button("Today") { viewModel.load(Date()) }
            }
        }
        ToolbarItem(placement: .principal) {
            if let viewModel {
                dayHeader(viewModel)
            }
        }
        // Stands in for the hidden status bar's clock, on today only: another
        // day adds a Today button, and the bar has no room for both.
        if hidesStatusBar, viewModel?.isToday ?? true {
            if #available(iOS 26.0, *) {
                // Plain text, not a glass button beside the classroom button.
                clockItem.sharedBackgroundVisibility(.hidden)
            } else {
                clockItem
            }
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

    private var clockItem: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            TimelineView(.everyMinute) { context in
                // As the status bar shows it ("8:24 AM"): omitting AM/PM
                // makes the formatter pad the hour ("08:24").
                Text(context.date.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .fixedSize() // iOS 27's toolbar otherwise truncates it to "1:43…".
            }
        }
    }

    private func dayHeader(_ viewModel: AssistantAttendanceViewModel) -> some View {
        HStack(spacing: 4) {
            Button {
                step(viewModel, forward: false)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous school day")

            Button {
                showingDatePicker = true
            } label: {
                // One line: "Today  Tue, Sep 29", or just the date on
                // another day.
                HStack(spacing: 5) {
                    if viewModel.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .accessibilityLabel("Locked")
                    }
                    if viewModel.isToday {
                        Text("Today")
                            .font(.headline)
                    }
                    Text(viewModel.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                        .font(viewModel.isToday ? .subheadline : .headline)
                        .foregroundStyle(viewModel.isToday ? .secondary : .primary)
                }
                .lineLimit(1)
                .foregroundStyle(.primary)
            }
            .accessibilityLabel(viewModel.date.formatted(date: .complete, time: .omitted))
            .accessibilityHint("Choose another day")

            Button {
                step(viewModel, forward: true)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next school day")
        }
    }

    /// A step through school days, the grid sliding in from that side.
    private func step(_ viewModel: AssistantAttendanceViewModel, forward: Bool) {
        stepEdge = forward ? .trailing : .leading
        withAnimation(.smooth(duration: 0.3)) {
            viewModel.step(forward: forward)
        }
    }

    /// A clearly sideways swipe steps a day; anything more vertical is left
    /// to scrolling, and a long press to the tile's menu.
    private func daySwipe(_ viewModel: AssistantAttendanceViewModel) -> some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard abs(dx) > 80, abs(dx) > abs(dy) * 2 else { return }
                step(viewModel, forward: dx < 0)
            }
    }

    // MARK: - Notices

    /// A locked day or a failed save, above the grid; nothing otherwise.
    @ViewBuilder
    private func notices(_ viewModel: AssistantAttendanceViewModel) -> some View {
        if viewModel.isLocked || viewModel.errorMessage != nil {
            VStack(alignment: .leading, spacing: 6) {
                if viewModel.isLocked {
                    Label("Your guide has locked this day.", systemImage: "lock.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
