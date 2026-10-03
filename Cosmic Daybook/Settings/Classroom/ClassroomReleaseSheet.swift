import SwiftUI

/// "Remove Last Year from the Share": what would leave, what to do first, then the run.
/// Nothing changes until the guide presses Back Up and Remove; the backup is made and
/// checked before any record is touched.
struct ClassroomReleaseSheet: View {
    let onFinished: () async -> Void

    @Environment(\.dependencies) private var dependencies
    @Environment(\.dismiss) private var dismiss
    @Environment(RestoreCoordinator.self) private var restoreCoordinator: RestoreCoordinator?
    @State private var model: ClassroomReleaseModel?

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            Text("Remove Last Year from the Share")
                .font(.title2.weight(.semibold))
            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            footer
        }
        .padding(AppTheme.Spacing.large)
        #if os(macOS)
        .frame(minWidth: 520, idealWidth: 560, minHeight: 440)
        #endif
        .interactiveDismissDisabled(model?.isWorking == true)
        .task {
            let restore = restoreCoordinator
            let made = ClassroomReleaseModel(dependencies: dependencies) { restore?.isRestoring ?? false }
            model = made
            await made.load()
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch model?.stage ?? .loading {
        case .loading:
            ProgressView("Reading what the share holds…")
        case .ready(let preview, let blocker):
            ready(preview, blocker: blocker)
        case .backingUp:
            ProgressView("Making a backup and checking it…")
        case .running(let done, let total):
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                ProgressView(value: Double(done), total: Double(max(total, 1)))
                Text("\(done) of \(total) groups done. Each waits until iCloud confirms it; keep this Mac "
                    + "awake and online. You can stop by quitting — nothing is lost, and running it again finishes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .finished(let report, let shareNow):
            finished(report, shareNow: shareNow)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColors.warning)
        }
    }

    @ViewBuilder
    private func ready(_ preview: ClassroomShareRelease.Preview, blocker: String?) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            let first = preview.cutoff.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
            Text("Everything from \(first), the first day of this school year, stays shared.")
                .font(.callout)
            if preview.isEmpty {
                Text("Nothing from before it is in the share.")
                if ClassroomShareRelease.stoppedPartway {
                    Text("An earlier run stopped after taking the last records out here. Finishing checks "
                        + "that iCloud has taken them out of the share too.")
                        .font(.callout)
                }
            } else {
                if !preview.children.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Leaving the share").font(.headline)
                        ForEach(preview.children) { child in
                            Text(childLine(child)).font(.callout)
                        }
                    }
                }
                if preview.olderAttendance > 0 {
                    Text("\(preview.olderAttendance.formatted()) attendance records from before that day, "
                        + "for children still in class, leave the share too.")
                        .font(.callout)
                }
                if preview.unfinished > 0 {
                    Text("\(preview.unfinished) record(s) from a run that stopped partway are finished too.")
                        .font(.callout)
                }
                checklist
            }
            if let blocker {
                Label(blocker, systemImage: "hand.raised.fill")
                    .foregroundStyle(AppColors.warning)
            }
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Before you start").font(.headline)
            Text("• Everything stays in your notebook; it only leaves your assistants' iPhones.")
            Text("• Close Cosmic Daybook on your iPhone and iPad until it finishes.")
            Text("• Turn off Claude Desktop access if it's on (Settings › Intelligence).")
            Text("• Keep this Mac awake and online. A backup is made and checked first.")
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    private func childLine(_ child: ClassroomShareRelease.DepartingChild) -> String {
        let left = child.departed.map { "left \($0.formatted(date: .abbreviated, time: .omitted))" }
            ?? "no leaving date"
        let marks = child.attendanceRecords == 1
            ? "1 attendance record"
            : "\(child.attendanceRecords) attendance records"
        return "\(child.name) — \(left), \(marks)"
    }

    @ViewBuilder
    private func finished(_ report: ClassroomShareRelease.Report, shareNow: String?) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            if let reason = report.stoppedBecause {
                Label(report.batchesPlanned > 0
                        ? "Stopped after \(report.batchesDone) of \(report.batchesPlanned) groups."
                        : "Stopped.",
                      systemImage: "pause.circle.fill")
                    .foregroundStyle(AppColors.warning)
                Text(reason).font(.callout)
            } else {
                Label("Done.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.success)
            }
            if report.batchesPlanned > 0 {
                Text("\(report.studentsMoved) student(s) and \(report.attendanceMoved.formatted()) attendance "
                    + "record(s) left the share. They're still in your notebook.")
                    .font(.callout)
            }
            if let shareNow {
                Text(shareNow).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Spacer()
            switch model?.stage ?? .loading {
            case .ready(let preview, let blocker):
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                if !preview.isEmpty {
                    Button("Back Up and Remove") {
                        Task { await model?.start() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(blocker != nil)
                } else if ClassroomShareRelease.stoppedPartway {
                    Button("Finish") {
                        Task { await model?.start() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(blocker != nil)
                }
            case .finished, .failed:
                Button("Done") {
                    Task {
                        await onFinished()
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
            case .loading, .backingUp, .running:
                EmptyView()
            }
        }
    }
}
