import CoreData

/// Centralized schema reference for the app.
/// The Core Data model is defined in the .xcdatamodeld file.
/// This struct provides a single place to reference the managed object model
/// used by both the production Core Data stack and preview containers.
struct AppSchema {
    /// The Core Data managed object model loaded from the app bundle.
    nonisolated(unsafe) static let managedObjectModel: NSManagedObjectModel = {
        guard let modelURL = Bundle.main.url(forResource: "MariasNotebook", withExtension: "momd"),
              let model = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Failed to load Core Data managed object model")
        }
        return model
    }()
}
