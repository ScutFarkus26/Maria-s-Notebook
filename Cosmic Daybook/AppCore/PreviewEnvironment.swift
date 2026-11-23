import SwiftUI
import CoreData
import OSLog

// Shared in-memory Core Data stack for previews across the project.
extension CoreDataStack {
    static let preview: CoreDataStack = {
        do {
            let stack = try CoreDataStack(enableCloudKit: false, inMemory: true)
            return stack
        } catch {
            logger.warning("Failed to create preview CoreDataStack: \(error)")
            fatalError("Failed to create preview CoreDataStack - this should never happen for in-memory containers")
        }
    }()
}

/// One restore coordinator for every preview: nothing restores there, so it
/// only has to exist for the screens that read it.
private let previewRestoreCoordinator = RestoreCoordinator()

extension View {
    /// Apply a standard preview environment:
    /// - A shared in-memory Core Data stack for the app's schema
    /// - A `SaveCoordinator.preview` that suppresses alerts
    /// - The album library and a restore coordinator, which lesson and
    ///   detail screens read without a fallback
    /// Use this in every `#Preview` to avoid missing environment wiring.
    func previewEnvironment() -> some View {
        previewEnvironment(using: CoreDataStack.preview)
    }

    /// Variant that uses a specific stack (e.g., when seeding data in the preview)
    func previewEnvironment(using stack: CoreDataStack) -> some View {
        self
            .environment(\.managedObjectContext, stack.viewContext)
            .environment(SaveCoordinator.preview)
            .environment(AlbumLibrary.shared)
            .environment(previewRestoreCoordinator)
    }
}
