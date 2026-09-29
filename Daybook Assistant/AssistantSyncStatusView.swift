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
/// began after the save finishes successfully.
struct AssistantSyncStatusView: View {
    let coreDataStack: CoreDataStack

    /// Kept across launches: marks saved just before the app was closed are
    /// still unsent until the next launch's export says otherwise.
    @AppStorage("Assistant.lastSharedSave") private var lastSharedSave: Double = 0
    @AppStorage("Assistant.lastSharedExportStart") private var lastSharedExportStart: Double = 0
    @State private var hasUnsavedChanges = false
    @State private var lastExportFailed = false

    private enum Status {
        case sent, sending, waitingForNetwork
    }

    private var status: Status {
        if hasUnsavedChanges || lastSharedSave > lastSharedExportStart {
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
        ) { note in
            refreshUnsavedChanges()
            if savedIntoSharedStore(note) {
                lastSharedSave = Date().timeIntervalSince1970
            }
        }
        .task { await observeSharedExports() }
    }

    @ViewBuilder
    private var statusLine: some View {
        HStack(spacing: 6) {
            if isSampleClass {
                Image(systemName: "icloud.slash")
                Text("Sample class. Nothing goes to iCloud.")
            } else {
                switch status {
                case .sent:
                    Image(systemName: "checkmark.icloud")
                    Text("All marks sent to iCloud")
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

    /// The sample class lives in memory with no iCloud behind it, so "sent"
    /// would be untrue.
    private var isSampleClass: Bool {
        #if DEBUG
        AssistantSampleClass.isRequested
        #else
        false
        #endif
    }

    private func refreshUnsavedChanges() {
        let pending = coreDataStack.viewContext.hasChanges
        if pending != hasUnsavedChanges { hasUnsavedChanges = pending }
    }

    /// Whether the save touched the shared store. Her name and membership
    /// rows live in her private store and never go to the guide, so a save of
    /// only those must not leave the line stuck on "Sending".
    private func savedIntoSharedStore(_ note: Notification) -> Bool {
        guard let shared = coreDataStack.sharedPersistentStore else { return false }
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]
        return keys.contains { key in
            ((note.userInfo?[key] as? Set<NSManagedObject>) ?? []).contains {
                $0.objectID.persistentStore === shared
            }
        }
    }

    private func observeSharedExports() async {
        guard let storeID = coreDataStack.sharedPersistentStore?.identifier else { return }
        let exports = NotificationCenter.default
            .notifications(named: NSPersistentCloudKitContainer.eventChangedNotification)
            .compactMap { Self.finishedExport(in: $0, storeID: storeID) }
        for await export in exports {
            lastExportFailed = !export.succeeded
            if export.succeeded {
                lastSharedExportStart = max(lastSharedExportStart, export.startDate.timeIntervalSince1970)
            }
        }
    }

    private struct FinishedExport: Sendable {
        let startDate: Date
        let succeeded: Bool
    }

    /// Read off the notification before it reaches the main actor:
    /// `Notification` isn't Sendable.
    private nonisolated static func finishedExport(in note: Notification, storeID: String) -> FinishedExport? {
        guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event,
              event.type == .export, event.endDate != nil,
              event.storeIdentifier == storeID
        else { return nil }
        return FinishedExport(startDate: event.startDate, succeeded: event.succeeded)
    }
}
