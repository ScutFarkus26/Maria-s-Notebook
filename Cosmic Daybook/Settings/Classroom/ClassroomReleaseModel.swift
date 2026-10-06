import CloudKit
import CoreData
import Foundation
import OSLog

/// Drives "Remove Last Year from the Share": the preview, the checks, the verified backup,
/// the run and its report (`ClassroomShareRelease`).
@Observable @MainActor
final class ClassroomReleaseModel {
    enum Stage: Equatable {
        case loading
        /// Ready to confirm, or blocked with the reason.
        case ready(ClassroomShareRelease.Preview, blocker: String?)
        case backingUp
        case running(done: Int, total: Int)
        case finished(ClassroomShareRelease.Report, shareNow: String?)
        /// Why it couldn't go on, plainly, and the technical reason for Details.
        case failed(String, details: String? = nil)
    }

    private(set) var stage: Stage = .loading
    /// Why the last press didn't start, shown above a preview made again: what would leave
    /// changed after the guide read it (`ClassroomShareRelease.changeSincePreview`).
    private(set) var notice: String?
    private let dependencies: AppDependencies
    private let isRestoring: () -> Bool
    private static let logger = Logger.classroomSharing

    init(dependencies: AppDependencies, isRestoring: @escaping () -> Bool) {
        self.dependencies = dependencies
        self.isRestoring = isRestoring
    }

    var isWorking: Bool {
        switch stage {
        case .backingUp, .running: return true
        default: return false
        }
    }

    // MARK: - Preview

    func load() async {
        stage = .loading
        notice = nil
        let stack = dependencies.coreDataStack
        do {
            guard let preview = try await ClassroomShareRelease.preview(coreDataStack: stack) else {
                stage = .failed(Self.unreadable)
                return
            }
            stage = .ready(preview, blocker: blocker(for: preview))
        } catch {
            stage = Self.readFailed(error)
        }
    }

    /// Every reason not to start, the last one being the cutoff check (#1 in the plan): a
    /// start date set later than the first day school met would take this year's first
    /// marks out of the share.
    private func blocker(for preview: ClassroomShareRelease.Preview) -> String? {
        let stack = dependencies.coreDataStack
        if let reason = ClassroomShareRelease.blocker(coreDataStack: stack, isRestoring: isRestoring()) {
            return reason
        }
        return cutoffBlocker(for: preview)
    }

    private func cutoffBlocker(for preview: ClassroomShareRelease.Preview) -> String? {
        let stack = dependencies.coreDataStack
        return ClassroomShareRelease.cutoffBlocker(
            preview.cutoff, context: stack.viewContext, store: stack.privatePersistentStore
        )
    }

    // MARK: - Running

    func start() async {
        guard case .ready(let preview, nil) = stage,
              !preview.isEmpty || ClassroomShareRelease.stoppedPartway else { return }
        let stack = dependencies.coreDataStack
        // Checked again: time passed while the guide read the preview. It includes a run
        // already going in another window, and nothing suspends between it and the claim.
        if let reason = ClassroomShareRelease.blocker(coreDataStack: stack, isRestoring: isRestoring()) {
            stage = .ready(preview, blocker: reason)
            return
        }
        guard let store = stack.privatePersistentStore,
              let zone = CDClassroomMembership.pinnedZoneName(in: stack.viewContext) else {
            stage = .failed(Self.unreadable)
            return
        }
        guard ClassroomShareRelease.claimRun() else {
            stage = .ready(preview, blocker: ClassroomShareRelease.runningMessage)
            return
        }
        defer { ClassroomShareRelease.endRun() }
        notice = nil
        if preview.isEmpty {
            await finishStoppedRun(zone: zone, storeID: store.identifier)
        } else {
            await backUpAndRun(confirmed: preview, storeID: store.identifier, zone: zone)
        }
    }

    private func backUpAndRun(confirmed preview: ClassroomShareRelease.Preview, storeID: String, zone: String) async {
        let stack = dependencies.coreDataStack
        stage = .backingUp
        // The backup is made before anything is touched; then the plan is made again, since
        // the preview may be minutes old, and the backup must hold every record it names.
        guard let backup = await makeBackup(), let fresh = await replan(),
              stillAsConfirmed(fresh, confirmed: preview),
              await checkBackup(backup, holds: fresh) else { return }

        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: "Removing last year's records from the classroom share"
        )
        defer { ProcessInfo.processInfo.endActivity(activity) }
        UserDefaults.standard.set(Date(), forKey: ClassroomShareRelease.inProgressKey)

        stage = .running(done: 0, total: fresh.batches.count)
        let report = await ClassroomShareRelease.run(
            fresh.batches,
            container: stack.container,
            storeID: storeID,
            environment: .live(container: stack.container)
        ) { [weak self] done, total in
            await MainActor.run { self?.stage = .running(done: done, total: total) }
        }
        if report.stoppedBecause == nil {
            UserDefaults.standard.removeObject(forKey: ClassroomShareRelease.inProgressKey)
        }
        stage = .finished(report, shareNow: await serverSummary(zone: zone))
    }

    /// False (with the new preview shown, and why) when `fresh`, planned again after the
    /// backup, isn't what the guide confirmed (another start date, records she wasn't shown),
    /// or fails the start-date check run again on its own start: attendance may have been
    /// taken since the preview.
    private func stillAsConfirmed(
        _ fresh: ClassroomShareRelease.Preview, confirmed preview: ClassroomShareRelease.Preview
    ) -> Bool {
        let early = cutoffBlocker(for: fresh)
        if let change = ClassroomShareRelease.changeSincePreview(fresh, confirmed: preview) {
            Self.logger.notice("Release: the plan changed since the preview; not started")
            notice = change
            stage = .ready(fresh, blocker: early)
            return false
        }
        if let early {
            stage = .ready(fresh, blocker: early)
            return false
        }
        return true
    }

    /// A run that stopped after its last deletes were saved here leaves nothing to plan, and
    /// the flag would never clear: only iCloud's confirmation is left to wait for. Nothing in
    /// the notebook changes, so no backup is made.
    private func finishStoppedRun(zone: String, storeID: String) async {
        let container = dependencies.coreDataStack.container
        stage = .running(done: 0, total: 1)
        let report = await ClassroomShareRelease.finishStopped(
            container: container, storeID: storeID, environment: .live(container: container)
        )
        if report.stoppedBecause == nil {
            UserDefaults.standard.removeObject(forKey: ClassroomShareRelease.inProgressKey)
        }
        stage = .finished(report, shareNow: await serverSummary(zone: zone))
    }

    /// Nil (with the stage set to say why) when the backup failed.
    private func makeBackup() async -> URL? {
        do {
            return try await ClassroomShareRelease.backUp(
                coreDataStack: dependencies.coreDataStack, backups: dependencies.autoBackupManager
            )
        } catch {
            Self.logger.error("Release: backup failed: \(error.localizedDescription, privacy: .public)")
            stage = .failed(
                AppErrorMessages.backupMessage(for: error, operation: "make the backup, so nothing was changed")
            )
            return nil
        }
    }

    /// False (with the stage set to say why) when the backup doesn't hold every record
    /// `plan` touches.
    private func checkBackup(_ url: URL, holds plan: ClassroomShareRelease.Preview) async -> Bool {
        do {
            try await ClassroomShareRelease.checkBackup(
                url, holds: plan.batches, container: dependencies.coreDataStack.container
            )
            Self.logger.notice("Release: verified backup \(url.lastPathComponent, privacy: .public)")
            return true
        } catch {
            // The check names what was missing ("The backup holds 12 Student records, the
            // notebook 14"): that's for Details.
            Self.logger.error("Release: backup check failed: \(error.localizedDescription, privacy: .public)")
            stage = .failed(
                "The safety backup didn't hold all of your notebook, so nothing was changed. Try again.",
                details: error.localizedDescription
            )
            return false
        }
    }

    private func replan() async -> ClassroomShareRelease.Preview? {
        do {
            if let planned = try await ClassroomShareRelease.preview(coreDataStack: dependencies.coreDataStack) {
                return planned
            }
            stage = .failed(Self.unreadable)
        } catch {
            stage = Self.readFailed(error)
        }
        return nil
    }

    private static let unreadable = "Couldn't read the classroom share right now. Reopen Settings and try again."

    private static func readFailed(_ error: Error) -> Stage {
        let ns = error as NSError
        let details = "\(ns.domain) \(ns.code): \(ns.localizedDescription)"
        logger.error("Release: reading the share failed: \(details, privacy: .public)")
        return .failed(
            "Couldn't read the classroom share from iCloud. Check you're online and try again.", details: details
        )
    }

    /// What the share holds now, as the CloudKit server itself counts it. Nil when the server
    /// doesn't answer in time (`CloudKitServerCheck.requestTimeout`): the sheet must reach
    /// its Done button either way.
    private func serverSummary(zone: String) async -> String? {
        let database = CloudKitConfigurationService.container.privateCloudDatabase
        let read = try? await CloudKitServerCheck.withTimeout {
            try await CloudKitServerCheck.recordTypeCounts(inZone: zone, database: database)
        }
        guard let counts = read else { return nil }
        let students = counts["CD_Student", default: 0]
        let marks = counts["CD_AttendanceRecord", default: 0]
        return "Your assistants now see \(students) child\(students == 1 ? "" : "ren") and "
            + "\(marks.formatted()) attendance mark\(marks == 1 ? "" : "s")."
    }
}
