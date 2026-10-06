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
                Text("\(done) of \(total) steps done. Each waits until iCloud confirms it; keep this Mac "
                    + "awake and online. You can stop by quitting — nothing is lost, and running it again finishes.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        case .finished(let report, let shareNow):
            finished(report, shareNow: shareNow)
        case .failed(let message, let details):
            VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(AppColors.warning)
                if let details {
                    TechnicalDetailsDisclosure(details: details)
                }
            }
        }
    }

    @ViewBuilder
    private func ready(_ preview: ClassroomShareRelease.Preview, blocker: String?) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            if let notice = model?.notice {
                Label(notice, systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(AppColors.warning)
            }
            let first = preview.cutoff.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
            Text("Everything from \(first), the first day of this school year, stays shared.")
                .font(.callout)
            if preview.isEmpty {
                Text(preview.leftShared.isEmpty
                    ? "Nothing from before it is in the share."
                    : "Nothing from before it can leave the share right now.")
                if ClassroomShareRelease.stoppedPartway {
                    Text("An earlier run stopped just before the end. Finishing checks that iCloud "
                        + "has stopped sharing them too.")
                        .font(.callout)
                }
            } else {
                leaving(preview)
                checklist
            }
            if !preview.leftShared.isEmpty {
                leftSharedList(preview.leftShared)
            }
            if let blocker {
                Label(blocker, systemImage: "hand.raised.fill")
                    .foregroundStyle(AppColors.warning)
            }
        }
    }

    /// Who and what leaves the share.
    @ViewBuilder
    private func leaving(_ preview: ClassroomShareRelease.Preview) -> some View {
        if !preview.children.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Leaving the share").font(.headline)
                ForEach(preview.children) { child in
                    Text(childLine(child)).font(.callout)
                }
            }
        }
        if preview.olderAttendance > 0 {
            Text(Self.olderLine(preview.olderAttendance, children: "children in this year's class"))
                .font(.callout)
        }
        if preview.olderAttendanceOfChildrenWhoLeft > 0 {
            Text(Self.olderLine(preview.olderAttendanceOfChildrenWhoLeft, children: "children no longer in your class"))
                .font(.callout)
        }
        if preview.unfinished > 0 {
            Text(preview.unfinished == 1
                ? "1 item from a run that stopped partway is finished too."
                : "\(preview.unfinished.formatted()) items from a run that stopped partway are finished too.")
                .font(.callout)
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

    /// "412 attendance marks from before that day, for children in this year's class, stop
    /// being shared too."
    static func olderLine(_ count: Int, children: String) -> String {
        count == 1
            ? "1 attendance mark from before that day, for \(children), stops being shared too."
            : "\(count.formatted()) attendance marks from before that day, for \(children), stop being shared too."
    }

    /// The records a backup can't hold, so the run leaves them shared: named, so the
    /// count Settings showed adds up.
    private func leftSharedList(_ records: [ClassroomShareRelease.LeftShared]) -> some View {
        let shown = 10
        return VStack(alignment: .leading, spacing: 4) {
            Text("Staying in the share").font(.headline)
            Text("A backup can't hold these, so they aren't removed. They stay in your notebook too.")
                .foregroundStyle(.secondary)
            ForEach(records.prefix(shown)) { record in
                Text("• " + Self.leftSharedLine(record))
            }
            if records.count > shown {
                Text("• and \((records.count - shown).formatted()) more")
            }
        }
        .font(.callout)
    }

    /// "A mark for Maya Cedar with no date".
    static func leftSharedLine(_ record: ClassroomShareRelease.LeftShared) -> String {
        let day = record.date?.formatted(date: .abbreviated, time: .omitted)
        if record.entity == "Student" {
            return "\(record.childName ?? "A child")'s record is incomplete"
        }
        switch record.gap {
        case .noDate:
            return record.childName.map { "A mark for \($0) with no date" } ?? "A mark with no date or child"
        case .noChild:
            let mark = day.map { "A mark from \($0)" } ?? "A mark"
            return record.childName.map { "\(mark) whose link to \($0) is damaged" } ?? "\(mark) not linked to a child"
        case .noID:
            let mark = record.childName.map { "A mark for \($0)" } ?? "A mark"
            return day.map { "\(mark) from \($0) is incomplete" } ?? "\(mark) is incomplete"
        }
    }

    private func childLine(_ child: ClassroomShareRelease.DepartingChild) -> String {
        let left = child.departed.map { "left \($0.formatted(date: .abbreviated, time: .omitted))" }
            ?? "no leaving date"
        let marks = child.attendanceRecords == 1
            ? "1 attendance mark"
            : "\(child.attendanceRecords.formatted()) attendance marks"
        return "\(child.name) — \(left), \(marks)"
    }

    @ViewBuilder
    private func finished(_ report: ClassroomShareRelease.Report, shareNow: String?) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            if let reason = report.stoppedBecause {
                // The reason says that nothing is lost and what to do next.
                Label(report.batchesPlanned > 0
                        ? "Stopped partway (\(report.batchesDone) of \(report.batchesPlanned) steps)."
                        : "Stopped.",
                      systemImage: "pause.circle.fill")
                    .foregroundStyle(AppColors.warning)
                Text(reason).font(.callout)
                if let details = report.stopDetails {
                    TechnicalDetailsDisclosure(details: details)
                }
            } else {
                Label("Done.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.success)
            }
            if report.batchesPlanned > 0 {
                Text(Self.movedLine(report))
                    .font(.callout)
            }
            if let deleted = Self.deletedElsewhereLine(report) {
                Text(deleted).font(.callout)
            }
            if let shareNow {
                Text(shareNow).font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    /// "3 children and 412 attendance marks are no longer shared."
    static func movedLine(_ report: ClassroomShareRelease.Report) -> String {
        let children = report.studentsMoved == 1 ? "1 child" : "\(report.studentsMoved.formatted()) children"
        let marks = report.attendanceMoved == 1
            ? "1 attendance mark" : "\(report.attendanceMoved.formatted()) attendance marks"
        return "\(children) and \(marks) are no longer shared. They're still in your notebook."
    }

    /// Records another device deleted while the run went: not moved, so not in `movedLine`.
    static func deletedElsewhereLine(_ report: ClassroomShareRelease.Report) -> String? {
        switch report.deletedElsewhere {
        case 0: return nil
        case 1: return "1 item was deleted on another device while this ran, so it's gone from your notebook too."
        default:
            return "\(report.deletedElsewhere.formatted()) items were deleted on another device while this ran, "
                + "so they're gone from your notebook too."
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
