import Foundation
import CoreData
import OSLog

/// Her name, kept where the shared attendance code reads it
/// (`ClassroomIdentity.displayName`, on this iPhone) and mirrored to iCloud
/// key-value storage, so a new iPhone on her Apple Account already knows it
/// instead of asking again and marking under no name until she answers.
///
/// Key-value storage follows her Apple Account, not the guide's, so that copy
/// is hers alone. The guide's devices read her name from the classroom's list
/// of names (`ClassroomNames`), which `save(_:in:)` also sets, so a rename
/// reaches her old marks there too.
enum AssistantNameStore {
    private static let key = "Assistant.displayName"
    private static let logger = Logger.app(category: "names")

    static func save(_ name: String) {
        ClassroomIdentity.displayName = name
        let store = NSUbiquitousKeyValueStore.default
        if let saved = ClassroomIdentity.displayName {
            store.set(saved, forKey: key)
        } else {
            store.removeObject(forKey: key)
        }
    }

    /// Saves her name on this iPhone (`save(_:)`) and in the classroom's list
    /// of names on `stack`. The sample class's list is its own and gets
    /// nothing. Returns false when the list's save failed; her name is still
    /// kept on this iPhone, and the next launch writes it to the list
    /// (`ClassroomNames.writeWaitingName`).
    @discardableResult
    static func save(_ name: String, in stack: CoreDataStack?) -> Bool {
        save(name)
        guard let stack, !AssistantSampleClass.isActive else { return true }
        return setInList(name, in: stack.viewContext) { context, created in
            saveList(context, created: created, container: stack.container)
        }
    }

    /// Sets her row in the classroom's list (`ClassroomNames.setMyName`) and
    /// saves it with `save`, passing a new row so it goes into the share.
    /// Before her record name is known the name waits instead, and nothing
    /// is saved. Tests pass their own save.
    @discardableResult
    static func setInList(
        _ name: String,
        in context: NSManagedObjectContext,
        save: (_ context: NSManagedObjectContext, _ created: [NSManagedObject]) -> Bool
    ) -> Bool {
        guard let written = ClassroomNames.setMyName(name, role: .assistant, in: context) else { return true }
        guard written.isNew || written.person.hasChanges else { return true }
        return save(context, written.isNew ? [written.person] : [])
    }

    /// At launch, once her record name has been asked for: a name she gave
    /// before it was known (or before the classroom's list of names existed)
    /// joins the list, into the share (`ClassroomNames.writeWaitingName`).
    /// Never for the Debug launch's sample class, whose stack `stack` is then.
    static func writeWaitingName(on stack: CoreDataStack) {
        guard !AssistantSampleClass.isRequested else { return }
        writeWaitingName(in: stack.viewContext, container: stack.container)
    }

    /// `writeWaitingName(on:)`'s work; tests pass no container (no share).
    @discardableResult
    static func writeWaitingName(
        in context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer?
    ) -> Bool {
        ClassroomNames.writeWaitingName(role: .assistant, in: context) { context, created in
            saveList(context, created: created, container: container)
        }
    }

    /// Saves the list through `AssistantSave`, which puts a new row into the
    /// classroom share. A failed save takes a new row back out of the
    /// context, so no later save (the grid's, Restock's) writes it outside
    /// the share; her name stays on this iPhone, and the next launch writes
    /// it again.
    static func saveList(
        _ context: NSManagedObjectContext,
        created: [NSManagedObject],
        container: NSPersistentCloudKitContainer?
    ) -> Bool {
        if AssistantSave.save(context, container: container, created: created) { return true }
        logger.error("Saving her name to the classroom's list failed; it's written again at the next launch")
        for object in created where object.isInserted { context.delete(object) }
        return false
    }

    /// Fills in a missing name from iCloud. Returns whether it did.
    @discardableResult
    static func restoreIfNeeded() -> Bool {
        guard ClassroomIdentity.displayName == nil,
              let stored = NSUbiquitousKeyValueStore.default.string(forKey: key)?.trimmed(),
              !stored.isEmpty
        else { return false }
        ClassroomIdentity.displayName = stored
        return true
    }
}
