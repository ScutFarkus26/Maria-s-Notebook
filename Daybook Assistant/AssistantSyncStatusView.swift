import SwiftUI
import CoreData

/// A quiet line telling the assistant whether her marks have reached iCloud.
///
/// She has no way to inspect sync and no reason to learn how, so this reports
/// only the two states that change what she should do: everything's away, or
/// hold on to your phone a moment longer.
struct AssistantSyncStatusView: View {
    let coreDataStack: CoreDataStack

    @State private var hasPendingChanges = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: hasPendingChanges ? "arrow.triangle.2.circlepath" : "checkmark.icloud")
            Text(hasPendingChanges ? "Saving to iCloud…" : "All marks saved")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        // `hasChanges` can only move when the context's objects change (an
        // edit, a rollback, a reset) or it saves, so read it then instead of
        // polling every 3 s.
        .onAppear(perform: refresh)
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSManagedObjectContextObjectsDidChange, object: coreDataStack.viewContext
            )
        ) { _ in refresh() }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .NSManagedObjectContextDidSave, object: coreDataStack.viewContext
            )
        ) { _ in refresh() }
    }

    private func refresh() {
        let pending = coreDataStack.viewContext.hasChanges
        if pending != hasPendingChanges { hasPendingChanges = pending }
    }
}
