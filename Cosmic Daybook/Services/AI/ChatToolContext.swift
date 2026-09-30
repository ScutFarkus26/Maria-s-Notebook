import CoreData

/// The store Ask AI's notebook tools read: the classroom the chat is
/// answering in. `ChatService` sets it before each answer.
///
/// The tools used to open the guide's own notebook whatever the window
/// showed, so Ask AI in Sample Class answered with her real children's
/// notes. The model framework calls the tools on tasks of its own, so the
/// context can't travel as a task-local; one chat answers at a time.
@MainActor
enum ChatToolContext {
    private static weak var current: NSManagedObjectContext?

    static func use(_ context: NSManagedObjectContext) {
        current = context
    }

    /// The chat's classroom, else the guide's own notebook.
    static var context: NSManagedObjectContext {
        current ?? AppBootstrapping.getSharedCoreDataStack().viewContext
    }

    /// Whether that is the guide's own notebook: the search index covers
    /// only hers.
    static var readsGuidesNotebook: Bool {
        context === AppBootstrapping.getSharedCoreDataStack().viewContext
    }
}
