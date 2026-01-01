import SwiftUI
import SwiftData

// Shared in-memory container for previews across the project.
extension ModelContainer {
    static let preview: ModelContainer = {
        let schema = AppSchema.schema
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: configuration)
    }()
}

public extension View {
    /// Apply a standard preview environment:
    /// - A shared in-memory SwiftData container for the app's schema
    /// - A `SaveCoordinator.preview` that suppresses alerts
    /// Use this in every `#Preview` to avoid missing environment wiring.
    func previewEnvironment() -> some View {
        self
            .modelContainer(ModelContainer.preview)
            .environmentObject(SaveCoordinator.preview)
    }

    /// Variant that uses a specific container (e.g., when seeding data in the preview)
    func previewEnvironment(using container: ModelContainer) -> some View {
        self
            .modelContainer(container)
            .environmentObject(SaveCoordinator.preview)
    }
}
