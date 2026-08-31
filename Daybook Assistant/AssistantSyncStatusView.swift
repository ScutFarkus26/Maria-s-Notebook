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
        .task {
            while !Task.isCancelled {
                hasPendingChanges = coreDataStack.viewContext.hasChanges
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}
