import SwiftUI
import CoreData

/// A quiet line telling the assistant whether her marks have reached iCloud.
///
/// She has no way to inspect sync and no reason to learn how, so this reports
/// only the states that change what she should do: everything's away, hold on
/// to your phone a moment longer, it'll go once you're back online, or iCloud
/// is hard to reach right now and the app keeps trying.
///
/// "Away" means CloudKit says so. A saved context only means the marks are on
/// this phone. A new mark has reached the guide once the share step
/// (`AssistantShareAttacher`) has put it into the classroom share, which it
/// counts until then. An edit or a removal of a record already there goes by
/// Core Data's own upload of the shared store (the only store her marks are
/// written to, see `CDAttendanceStore`): it has gone once an export that
/// began after the save finishes successfully. The saves and exports are
/// recorded for the whole app (`AssistantSyncRecord`), not by this line.
/// Every save used to wait for an export, so while iCloud couldn't be
/// reached the line read "Not sent yet" all morning though every mark had
/// gone by the share step (2026-10-22).
///
/// When iCloud can't be reached though the phone is on a network, the line
/// doesn't blame the network: the same morning, the fault was most likely a
/// stalled upload on the phone, which a change of network restarted, and
/// the app now restarts that itself (`AssistantBootstrapper.sendStalled`).
struct AssistantSyncStatusView: View {
    let coreDataStack: CoreDataStack
    @Environment(AssistantBootstrapper.self) private var bootstrapper
    @State private var hasUnsavedChanges = false

    static var lastSharedEditSaveKey: String { AssistantSyncRecord.lastSharedEditSaveKey }
    static var lastSharedExportStartKey: String { AssistantSyncRecord.lastSharedExportStartKey }
    static var lastSharedImportEndKey: String { AssistantSyncRecord.lastSharedImportEndKey }

    enum Status: Equatable {
        case sent
        case sending
        /// The last upload failed for a reason other than the network, and
        /// an edit waits for it; Core Data tries again by itself.
        case tryingAgain
        /// iCloud couldn't be reached, and the phone has no usable network
        /// (or none known yet).
        case offline
        /// iCloud couldn't be reached though the phone is on a network. Why
        /// can't be told from here (a stalled upload, a slow link, a network
        /// that blocks iCloud), so the line names no culprit; the share step
        /// retries, and sending that keeps failing on a usable network
        /// restarts the stack (`AssistantBootstrapper.sendStalled`).
        case troubleReachingICloud
    }

    /// When iCloud sync has stopped on this iPhone (`AssistantBootstrapper.sendingStopped`).
    static let sendingStoppedMessage = "Marks aren't sending. Quit the app and open it again."

    /// The open stack's record; none for the Debug launch's sample class,
    /// whose line says nothing goes to iCloud anyway.
    private var record: AssistantSyncRecord? { AssistantStack.syncRecord }

    private var status: Status {
        Self.status(
            hasUnsavedChanges: hasUnsavedChanges,
            lastEditSave: record?.lastEditSave ?? 0,
            lastExportStart: record?.lastExportStart ?? 0,
            lastExportFailure: record?.lastExportFailure,
            waitingForShare: AssistantShareAttacher.shared.pendingCount,
            shareOffline: AssistantShareAttacher.shared.isOffline,
            network: AssistantStack.networkWatch?.current
        )
    }

    /// Sent once nothing waits to go into the share and no edit waits for
    /// an upload (an export that began after it has finished). Otherwise
    /// sending, unless iCloud couldn't be reached: the share step said so
    /// with marks still waiting (`AssistantShareAttacher.isOffline`), or the
    /// last export failed on the network with an edit still waiting for one.
    /// Then the network the phone is on tells "back online" from "trouble
    /// reaching iCloud". A failed export of another kind with an edit
    /// waiting reads as trying again, not as offline.
    static func status(
        hasUnsavedChanges: Bool,
        lastEditSave: Double,
        lastExportStart: Double,
        lastExportFailure: AssistantSyncRecord.ExportFailure?,
        waitingForShare: Int = 0,
        shareOffline: Bool = false,
        network: AssistantNetworkWatch.PathState? = nil
    ) -> Status {
        let editWaits = lastEditSave > lastExportStart
        guard hasUnsavedChanges || waitingForShare > 0 || editWaits else { return .sent }
        let noConnection = (shareOffline && waitingForShare > 0) || (lastExportFailure == .network && editWaits)
        if noConnection {
            guard let network, network.usable else { return .offline }
            return .troubleReachingICloud
        }
        if lastExportFailure == .other, editWaits { return .tryingAgain }
        return .sending
    }

    /// iOS 26.4.0 dropped CloudKit's sync pushes, so the guide's changes only
    /// arrived after relaunching; 26.4.1 fixed it. The app still runs back to
    /// iOS 18, so this asks anyone on that one release to update.
    private static let needsOSUpdate: Bool = {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return version.majorVersion == 26 && version.minorVersion == 4 && version.patchVersion == 0
    }()

    var body: some View {
        VStack(spacing: 4) {
            if Self.needsOSUpdate {
                Label(
                    "Update to iOS 26.4.1 or later so the guide's changes arrive.",
                    systemImage: "exclamationmark.triangle"
                )
                .foregroundStyle(.orange)
            }
            statusLine
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        // `hasChanges` can only move when the context's objects change (an
        // edit, a rollback, a reset) or it saves, so read it then instead of
        // polling every 3 s.
        .onAppear(perform: refreshUnsavedChanges)
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSManagedObjectContextObjectsDidChange, object: coreDataStack.viewContext
            )
        ) { _ in refreshUnsavedChanges() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSManagedObjectContextDidSave, object: coreDataStack.viewContext
            )
        ) { _ in refreshUnsavedChanges() }
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 6) {
            if isSampleClass {
                Image(systemName: "icloud.slash")
                Text("Sample class. Nothing goes to iCloud.")
            } else if let problem = bootstrapper.accountStatus?.assistantProblem {
                // Marks stay on this iPhone until iCloud is back; saying
                // "sending" would be untrue.
                Image(systemName: "icloud.slash")
                Text(problem)
                    .foregroundStyle(.orange)
            } else if bootstrapper.sendingNeedsRelaunch {
                // iCloud sync stopped, or the class's iCloud setup failed,
                // and rebuilding the stack once didn't bring it back, or a
                // share call has run past its watchdog and may never return:
                // only reopening the app does.
                Image(systemName: "exclamationmark.icloud")
                Text(Self.sendingStoppedMessage)
                    .foregroundStyle(.orange)
            } else {
                let importEnd = record?.lastImportEnd ?? 0
                switch status {
                case .sent:
                    Image(systemName: "checkmark.icloud")
                    Text(importEnd > 0 ? "All marks sent" : "All marks sent to iCloud")
                    classUpdated(importEnd)
                case .sending:
                    Image(systemName: "arrow.triangle.2.circlepath")
                    Text("Sending to iCloud…")
                case .tryingAgain:
                    Image(systemName: "exclamationmark.icloud")
                    Text(Self.tryingAgainMessage)
                case .offline:
                    Image(systemName: "icloud.slash")
                    Text(Self.offlineMessage)
                case .troubleReachingICloud:
                    Image(systemName: "icloud.slash")
                    Text(Self.troubleReachingICloudMessage)
                }
            }
        }
    }

    static let tryingAgainMessage = "Couldn't send yet. Trying again."
    static let offlineMessage = "Not sent yet. They'll go when you're back online."

    /// Nothing for her to do: the app retries, and restarts its own sending
    /// when the failures keep coming. Build 024 told her the Wi-Fi wasn't
    /// reaching iCloud and to turn it off for a minute, a cause that was
    /// never shown (2026-10-22).
    static let troubleReachingICloudMessage = "Not sent yet. Having trouble reaching iCloud. Trying again."

    /// "· class updated 2 min ago", redrawn each minute only while on screen.
    @ViewBuilder
    private func classUpdated(_ importEnd: Double) -> some View {
        if importEnd > 0 {
            let date = Date(timeIntervalSince1970: importEnd)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                Text("· class updated \(Self.relative(date, now: context.date))")
            }
        }
    }

    /// "just now" for the first minute, then "2 min. ago", "1 hr. ago".
    static func relative(_ date: Date, now: Date) -> String {
        guard now.timeIntervalSince(date) >= 60 else { return "just now" }
        return date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated))
    }

    /// The sample class has no iCloud behind it, so "sent"
    /// would be untrue.
    private var isSampleClass: Bool { AssistantSampleClass.isActive }

    private func refreshUnsavedChanges() {
        let pending = coreDataStack.viewContext.hasChanges
        if pending != hasUnsavedChanges { hasUnsavedChanges = pending }
    }
}
