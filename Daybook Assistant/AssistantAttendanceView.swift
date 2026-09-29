import SwiftUI
import CoreData

/// The whole app, once you've joined: one day's class, one tile each.
///
/// Two pills set what a tap means. **Arrival** marks a child present;
/// **Late** marks everyone still unmarked absent, after which a tap marks
/// tardy. Every mark carries its time.
///
/// The pills, the count and the iCloud line sit in the bottom bar, in thumb
/// reach and out of the grid's way: on a phone, three columns of short names
/// fit a class of up to 24 on one screen without scrolling.
///
/// It opens on today. The ‹ › arrows step through school days (skipping
/// weekends and the guide's days off), tapping the date opens a picker for any
/// day, past or future, and Today comes back. A day the guide has locked shows
/// a lock and read-only rows; `CDAttendanceStore` refuses edits to it anyway.
struct AssistantAttendanceView: View {
    let coreDataStack: CoreDataStack

    @State private var viewModel: AssistantAttendanceViewModel?
    @State private var showingNameSheet = false
    @State private var showingDatePicker = false
    @State private var noteRow: AssistantAttendanceViewModel.Row?
    /// The "Marked 3 absent · Undo" line after switching to Late. It stays
    /// until the next mark, a phase or day change, or the app leaving the
    /// foreground.
    @State private var lateUndo: LateUndo?
    @Namespace private var phaseNamespace
    /// Whether the screen was on today when the app last left the foreground:
    /// only then does coming back move it on to the new today.
    @State private var followsToday = true
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Phones: three columns of short names. Wider screens have room for
    /// full names.
    private var usesShortNames: Bool { horizontalSizeClass == .compact }

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
                bottomBar
            }
        }
        .sheet(isPresented: $showingNameSheet) {
            AssistantNameSheet()
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
                studentName: row.student.fullName,
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
        .onChange(of: viewModel?.date) {
            // Undo belongs to the day it was offered on.
            lateUndo = nil
        }
        .onChange(of: noteRow?.id) { _, editing in
            viewModel?.pauseRemoteReloads(editing != nil)
        }
        .onChange(of: scenePhase) { oldPhase, phase in
            if phase != .active { lateUndo = nil }
            guard let viewModel else { return }
            if phase == .active {
                // Left open overnight on today, the screen moves on to the new
                // today; left on another day, it stays there.
                if followsToday, !viewModel.isToday {
                    viewModel.load(Date())
                } else {
                    viewModel.load()
                }
            } else if oldPhase == .active {
                // Noted on the way out only: coming back passes through
                // .inactive after midnight, when "today" has already moved.
                followsToday = viewModel.isToday
            }
        }
    }

    /// The sample class marks under no one's name, so it doesn't ask.
    private var asksForName: Bool {
        #if DEBUG
        if AssistantSampleClass.isRequested { return false }
        #endif
        return ClassroomIdentity.displayName == nil
    }

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
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                showingNameSheet = true
            } label: {
                Label(ClassroomIdentity.displayName ?? "Your name", systemImage: "person.crop.circle")
                    .labelStyle(.iconOnly)
            }
            .accessibilityLabel("Your name")
        }
    }

    private func dayHeader(_ viewModel: AssistantAttendanceViewModel) -> some View {
        HStack(spacing: 4) {
            Button {
                viewModel.step(forward: false)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous school day")

            Button {
                showingDatePicker = true
            } label: {
                VStack(spacing: 1) {
                    HStack(spacing: 4) {
                        if viewModel.isLocked {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .accessibilityLabel("Locked")
                        }
                        Text(viewModel.isToday ? "Today" : "Attendance")
                            .font(.headline)
                    }
                    Text(viewModel.date.formatted(.dateTime.weekday(.wide).month().day()))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
            }
            .accessibilityLabel(viewModel.date.formatted(date: .complete, time: .omitted))
            .accessibilityHint("Choose another day")

            Button {
                viewModel.step(forward: true)
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel("Next school day")
        }
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
                Text(dayOffText(dayOff, isToday: viewModel.isToday))
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
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: usesShortNames ? 105 : 150), spacing: 10)],
                        spacing: 10
                    ) {
                        ForEach(viewModel.rows) { row in
                            tile(row, viewModel: viewModel)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 12)
            }
            .background(Color(.systemGroupedBackground))
            .refreshable { viewModel.load() }
        }
    }

    /// A new mark retires the Undo for the last switch to Late.
    private func tile(_ row: AssistantAttendanceViewModel.Row, viewModel: AssistantAttendanceViewModel) -> some View {
        AssistantAttendanceTile(
            row: row,
            phase: viewModel.phase,
            canMark: viewModel.canMark,
            usesShortName: usesShortNames,
            onTap: {
                lateUndo = nil
                viewModel.tap(row)
            },
            onSetStatus: {
                lateUndo = nil
                viewModel.setStatus($0, for: row)
            },
            onReason: { viewModel.setAbsenceReason($0, for: row) },
            onNote: { noteRow = row }
        )
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

    // MARK: - Bottom bar

    /// Phase pills, then the count (or the Undo for the last switch to Late,
    /// in the count's place so nothing above it moves), then the iCloud line.
    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let viewModel, viewModel.dayOff == nil, !viewModel.rows.isEmpty {
                if viewModel.canMark {
                    phasePills(viewModel)
                }
                Group {
                    if let lateUndo {
                        undoLine(lateUndo)
                            .transition(.opacity)
                    } else {
                        Text(tally(viewModel.rows))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .animation(.smooth, value: tally(viewModel.rows))
                            .transition(.opacity)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(minHeight: 22)
                .animation(.smooth(duration: 0.3), value: lateUndo?.id)
            }
            AssistantSyncStatusView(coreDataStack: coreDataStack)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(.bar)
    }

    /// Arrival · Late, as one quiet capsule; the chosen half slides. Before
    /// Late is switched on, its pill says what switching will do.
    private func phasePills(_ viewModel: AssistantAttendanceViewModel) -> some View {
        let unmarked = viewModel.rows.count { $0.status == .unmarked }
        let lateTitle = viewModel.phase == .arrival && unmarked > 0 ? "Late · \(unmarked) absent" : "Late"
        return HStack(spacing: 2) {
            phasePill("Arrival", phase: .arrival, viewModel: viewModel)
            phasePill(lateTitle, phase: .late, viewModel: viewModel)
        }
        .padding(3)
        .background(Color(.tertiarySystemFill), in: Capsule())
        .sensoryFeedback(.impact(weight: .light), trigger: viewModel.phase)
    }

    private func phasePill(
        _ title: String,
        phase: AssistantAttendanceViewModel.Phase,
        viewModel: AssistantAttendanceViewModel
    ) -> some View {
        let selected = viewModel.phase == phase
        return Button {
            guard !selected else { return }
            withAnimation(.smooth(duration: 0.3)) {
                switch phase {
                case .late:
                    let count = viewModel.beginLate()
                    lateUndo = count > 0 ? LateUndo(count: count) : nil
                case .arrival:
                    viewModel.returnToArrival()
                    lateUndo = nil
                }
            }
        } label: {
            Text(title)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background {
                    if selected {
                        Capsule()
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
                            .matchedGeometryEffect(id: "phase", in: phaseNamespace)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint(phase == .late ? "Marks everyone not yet here absent" : "")
    }

    /// "18 here · 2 absent · 1 late", leaving out what's zero.
    private func tally(_ rows: [AssistantAttendanceViewModel.Row]) -> String {
        let counts = Dictionary(grouping: rows, by: \.status).mapValues(\.count)
        let parts: [(AttendanceStatus, String)] = [
            (.present, "here"), (.tardy, "late"), (.absent, "absent"),
            (.leftEarly, "left early"), (.unmarked, "not marked")
        ]
        let text = parts.compactMap { status, word in
            counts[status].map { "\($0) \(word)" }
        }
        return text.joined(separator: " · ")
    }

    // MARK: - Undo

    private struct LateUndo: Equatable {
        let id = UUID()
        let count: Int
    }

    private func undoLine(_ undo: LateUndo) -> some View {
        HStack(spacing: 12) {
            Text("Marked \(undo.count) absent")
            Button("Undo") {
                withAnimation(.smooth(duration: 0.3)) {
                    viewModel?.returnToArrival(undo: true)
                    lateUndo = nil
                }
            }
            .fontWeight(.semibold)
            .foregroundStyle(.tint)
        }
    }

    private func dayOffText(_ dayOff: AssistantAttendanceViewModel.DayOff, isToday: Bool) -> String {
        switch dayOff {
        case .weekend:
            return isToday
                ? "It's the weekend. Attendance opens again on the next school day."
                : "That's a weekend. Use the arrows to move between school days."
        case .holiday(let reason?):
            return "\(reason). No attendance is taken on this day."
        case .holiday(nil):
            return "This is a day off on your guide's school calendar."
        }
    }
}

/// Picks any day, past or future. Days off can be chosen too; the screen then
/// says there's no school.
private struct AssistantDatePickerSheet: View {
    let onPick: (Date) -> Void
    @State private var selection: Date
    @Environment(\.dismiss) private var dismiss

    init(date: Date, onPick: @escaping (Date) -> Void) {
        self.onPick = onPick
        _selection = State(initialValue: date)
    }

    var body: some View {
        NavigationStack {
            DatePicker("Day", selection: $selection, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Choose a Day")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Show") {
                            onPick(selection)
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
