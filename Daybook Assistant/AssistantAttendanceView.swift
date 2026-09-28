import SwiftUI
import CoreData

/// The whole app, once you've joined: one day's class, one row each.
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
    /// Whether the screen was on today when the app last left the foreground:
    /// only then does coming back move it on to the new today.
    @State private var followsToday = true
    @Environment(\.scenePhase) private var scenePhase

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
            .safeAreaInset(edge: .bottom) {
                AssistantSyncStatusView(coreDataStack: coreDataStack)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
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
            if ClassroomIdentity.displayName == nil { showingNameSheet = true }
            if viewModel == nil { startDay() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard let viewModel else { return }
            switch phase {
            case .background, .inactive:
                followsToday = viewModel.isToday
            case .active:
                // Left open overnight on today, the screen moves on to the new
                // today; left on another day, it stays there.
                if followsToday, !viewModel.isToday {
                    viewModel.load(Date())
                } else {
                    viewModel.load()
                }
            @unknown default:
                break
            }
        }
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
            List {
                if viewModel.isLocked {
                    Label("Your guide has locked this day. Marks and notes can't be changed.", systemImage: "lock.fill")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Section {
                    ForEach(viewModel.rows) { row in
                        AssistantAttendanceRow(
                            row: row,
                            canMark: viewModel.canMark,
                            onCycle: { viewModel.cycleStatus(for: row) },
                            onReason: { viewModel.setAbsenceReason($0, for: row) },
                            onNote: { noteRow = row }
                        )
                    }
                } footer: {
                    if viewModel.canMark {
                        Text("Tap a student to change their mark. Swipe left to add a note.")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { viewModel.load() }
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
