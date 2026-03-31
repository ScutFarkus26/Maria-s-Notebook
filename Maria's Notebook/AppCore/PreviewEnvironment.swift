import SwiftUI
import CoreData
import OSLog

private let logger = Logger.app_

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

/// Helper utilities for creating preview containers.
@MainActor
enum PreviewEnvironment {
    /// Creates a preview Core Data stack.
    /// - Returns: A CoreDataStack configured for previews
    static func previewStack() -> CoreDataStack {
        CoreDataStack.preview
    }
}

extension View {
    /// Apply a standard preview environment:
    /// - A shared in-memory Core Data stack for the app's schema
    /// - A `SaveCoordinator.preview` that suppresses alerts
    /// Use this in every `#Preview` to avoid missing environment wiring.
    @MainActor
    func previewEnvironment() -> some View {
        self
            .environment(\.managedObjectContext, CoreDataStack.preview.viewContext)
            .environment(SaveCoordinator.preview)
    }

    /// Variant that uses a specific stack (e.g., when seeding data in the preview)
    @MainActor
    func previewEnvironment(using stack: CoreDataStack) -> some View {
        self
            .environment(\.managedObjectContext, stack.viewContext)
            .environment(SaveCoordinator.preview)
    }
}
