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
        .task {
            if viewModel == nil {
                let model = AssistantAttendanceViewModel(context: coreDataStack.viewContext)
                model.load()
                viewModel = model
            }
        }
    }

    @ViewBuilder
    private func content(_ viewModel: AssistantAttendanceViewModel) -> some View {
        if viewModel.rows.isEmpty {
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
                            onReason: { viewModel.setAbsenceReason($0, for: row) }
                        )
                    }
                } footer: {
                    Text("Tap a student to change their mark.")
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { viewModel.load() }
        }
    }
}
