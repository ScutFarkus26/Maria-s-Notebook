import SwiftUI
import CoreData

/// A quiet line telling the assistant whether her marks have reached iCloud.
///
/// She has no way to inspect sync and no reason to learn how, so this reports
/// only the states that change what she should do: everything's away, hold on
/// to your phone a moment longer, or it'll go once you're back online.
///
/// "Away" means CloudKit says so. A saved context only means the marks are on
/// this phone; they have reached the guide once an export of the shared store
/// (the only store her marks are written to, see `CDAttendanceStore`) that
/// began after the save finishes successfully, and none waits to go into the
/// classroom share (`AssistantShareAttacher`). The saves and exports are
/// recorded for the whole app (`AssistantSyncRecord`), not by this line.
struct AssistantSyncStatusView: View {
    let coreDataStack: CoreDataStack
    @Environment(AssistantBootstrapper.self) private var bootstrapper
    @State private var hasUnsavedChanges = false

    static var lastSharedSaveKey: String { AssistantSyncRecord.lastSharedSaveKey }
    static var lastSharedExportStartKey: String { AssistantSyncRecord.lastSharedExportStartKey }
    static var lastSharedImportEndKey: String { AssistantSyncRecord.lastSharedImportEndKey }

    enum Status: Equatable {
        case sent, sending, waitingForNetwork
    }

    /// When iCloud sync has stopped on this iPhone (`AssistantBootstrapper.sendingStopped`).
    static let sendingStoppedMessage = "Marks aren't sending. Quit the app and open it again."

    /// The open stack's record; none for the Debug launch's sample class,
    /// whose line says nothing goes to iCloud anyway.
    private var record: AssistantSyncRecord? { AssistantStack.syncRecord }

    private var status: Status {
        Self.status(
            hasUnsavedChanges: hasUnsavedChanges,
            lastSave: record?.lastSave ?? 0,
            lastExportStart: record?.lastExportStart ?? 0,
            lastExportFailed: record?.lastExportFailed ?? false,
            waitingForShare: AssistantShareAttacher.shared.pendingCount
        )
    }

    /// Sent once an export that began after the last save has finished and
    /// nothing waits to go into the share; until then sending, or waiting for
    /// the network when the last export failed.
    static func status(
        hasUnsavedChanges: Bool,
        lastSave: Double,
        lastExportStart: Double,
        lastExportFailed: Bool,
        waitingForShare: Int = 0
    ) -> Status {
        if hasUnsavedChanges || waitingForShare > 0 || lastSave > lastExportStart {
            return lastExportFailed ? .waitingForNetwork : .sending
        }
        return .sent
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
            } else if bootstrapper.sendingStopped {
                // iCloud sync stopped, and rebuilding the stack once didn't
                // bring it back: only reopening the app does.
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
                case .waitingForNetwork:
                    Image(systemName: "icloud.slash")
                    Text("Not sent yet. They'll go when you're back online.")
                }
            }
        }
    }

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
