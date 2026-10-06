import SwiftUI
import OSLog

/// Settings › Classroom on the Mac: this school year's attendance marks that are
/// in no share yet, with the count first and the one-time way to add them
/// (`ClassroomAttendanceCatchUp`). Shown only while there is something to add.
struct ClassroomAttendanceCatchUpCard: View {
    let onFinished: () async -> Void

    @Environment(\.dependencies) private var dependencies
    @Environment(\.scenePhase) private var scenePhase

    @State private var waiting: Int?
    @State private var showingConfirmation = false
    @State private var isAdding = false
    @State private var resultMessage: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            if let waiting, waiting > 0 {
                ClassroomShareBanner(
                    icon: "calendar.badge.plus",
                    tint: AppColors.warning,
                    title: ClassroomAttendanceCatchUp.title(waiting: waiting),
                    message: "Your assistants can't see them on their iPhones. Adding them changes nothing else; "
                        + "marks already in the share stay as they are."
                )
                addButton(waiting)
            }
            if let resultMessage {
                Text(resultMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(AppColors.destructive)
            }
        }
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await load() } }
        }
    }

    private func addButton(_ count: Int) -> some View {
        Button {
            showingConfirmation = true
        } label: {
            HStack(spacing: AppTheme.Spacing.small) {
                if isAdding {
                    ProgressView().controlSize(.small)
                }
                Label("Add This Year's Attendance to the Share…", systemImage: "person.2.badge.plus")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .disabled(isAdding)
        .confirmationDialog(
            "Add \(ClassroomShareSetupReport.describe(count, "AttendanceRecord")) to the share?",
            isPresented: $showingConfirmation,
            titleVisibility: .visible
        ) {
            Button("Add to the Share") { Task { await add() } }
        } message: {
            Text("They go into your classroom share, where your assistants see them. "
                + "Keep the app open until it finishes.")
        }
    }

    private func load() async {
        guard ClassroomAttendanceCatchUp.isAvailableHere, scenePhase == .active, !isAdding else { return }
        waiting = await ClassroomAttendanceCatchUp.count(coreDataStack: dependencies.coreDataStack)
    }

    private func add() async {
        isAdding = true
        defer { isAdding = false }
        resultMessage = nil
        errorMessage = nil
        do {
            let report = try await ClassroomAttendanceCatchUp.run(coreDataStack: dependencies.coreDataStack)
            resultMessage = report.summary
        } catch {
            let ns = error as NSError
            Logger.classroomSharing.error("""
                Adding this year's attendance to the share failed — \
                domain=\(ns.domain, privacy: .public) code=\(ns.code, privacy: .public)
                """)
            errorMessage = AppErrorMessages.sharingMessage(
                for: error, action: "add this year's attendance to the share"
            )
        }
        waiting = await ClassroomAttendanceCatchUp.count(coreDataStack: dependencies.coreDataStack)
        await onFinished()
    }
}
