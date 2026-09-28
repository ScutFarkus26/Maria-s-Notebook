import SwiftUI
import CoreData

/// The whole app, once you've joined: today's class, one row each.
///
/// Scoped to today on purpose. CloudKit sharing grants write access to the
/// whole shared zone, so the guarantee that an assistant only ever changes
/// today's attendance is one this screen makes, backed by ClassroomPermissions
/// underneath it.
struct AssistantAttendanceView: View {
    let coreDataStack: CoreDataStack

    @State private var viewModel: AssistantAttendanceViewModel?
    @State private var showingNameSheet = false
    @State private var noteRow: AssistantAttendanceViewModel.Row?
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingNameSheet = true
                    } label: {
                        Label(ClassroomIdentity.displayName ?? "Your name", systemImage: "person.crop.circle")
                            .labelStyle(.iconOnly)
                    }
                    .accessibilityLabel("Your name")
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text("Attendance").font(.headline)
                        Text(Date().formatted(.dateTime.weekday(.wide).month().day()))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
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
            // Left open overnight, the screen would still be showing
            // yesterday's roster (and yesterday's school-day answer).
            guard phase == .active, let viewModel else { return }
            if Calendar.current.isDateInToday(viewModel.date) {
                viewModel.load()
            } else {
                startDay()
            }
        }
    }

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
                Label("No School Today", systemImage: "sun.max")
            } description: {
                Text(dayOffText(dayOff))
            } actions: {
                Button("Check Again") { viewModel.load() }
            }
        } else if viewModel.rows.isEmpty {
            ContentUnavailableView {
                Label("No students yet", systemImage: "person.3")
            } description: {
                Text("The class list arrives from your guide's iPhone. It can take a minute after you join.")
            } actions: {
                Button("Check Again") { viewModel.load() }
            }
        } else {
            List {
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
                    Text("Tap a student to change their mark. Swipe left to add a note.")
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { viewModel.load() }
        }
    }

    private func dayOffText(_ dayOff: AssistantAttendanceViewModel.DayOff) -> String {
        switch dayOff {
        case .weekend:
            return "It's the weekend. Attendance opens again on the next school day."
        case .holiday(let reason?):
            return "\(reason). Attendance opens again on the next school day."
        case .holiday(nil):
            return "Today is a day off on your guide's school calendar."
        }
    }
}
