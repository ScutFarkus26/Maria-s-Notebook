import SwiftUI
import SwiftData
import OSLog

private let logger = Logger.app_

// Shared in-memory container for previews across the project.
extension ModelContainer {
    static let preview: ModelContainer = {
        let schema = AppSchema.schema
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        // In-memory containers should always succeed, but provide fallback
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            return container
        } catch {
            logger.warning("Failed to create preview ModelContainer: \(error)")
            fatalError("Failed to create preview ModelContainer - this should never happen for in-memory containers")
        }
    }()
    
    /// Creates a preview container with a specific schema.
    /// Use this for previews that need a subset of the full schema.
    static func previewContainer(for schema: Schema) -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: schema, configurations: configuration)
            return container
        } catch {
            logger.warning("Failed to create preview ModelContainer for schema: \(error)")
            fatalError("Failed to create preview ModelContainer for schema - this should never happen for in-memory containers")
        }
    }
}

/// Helper utilities for creating preview containers.
enum PreviewEnvironment {
    /// Creates a preview container for an array of model types.
    /// - Parameter types: Array of PersistentModel types
    /// - Returns: A ModelContainer configured for previews
    static func previewContainer(for types: [any PersistentModel.Type]) -> ModelContainer {
        let schema = Schema(types)
        return ModelContainer.previewContainer(for: schema)
    }
}

public extension View {
    /// Apply a standard preview environment:
    /// - A shared in-memory SwiftData container for the app's schema
    /// - A `SaveCoordinator.preview` that suppresses alerts
    /// Use this in every `#Preview` to avoid missing environment wiring.
    func previewEnvironment() -> some View {
        self
            .modelContainer(ModelContainer.preview)
            .environment(SaveCoordinator.preview)
    }

    /// Variant that uses a specific container (e.g., when seeding data in the preview)
    func previewEnvironment(using container: ModelContainer) -> some View {
        self
            .modelContainer(container)
            .environment(SaveCoordinator.preview)
    }
}
