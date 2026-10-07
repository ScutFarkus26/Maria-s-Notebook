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

    /// Set from an iCloud account change until the account has been read
    /// again (`AssistantBootstrapper.readAccountAgain`): her row would go
    /// under the last account's record name, which may be someone else's.
    /// Her name waits on this iPhone meanwhile.
    static var writesHeld = false

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
    static func save(_ name: String, in stack: CoreDataStack?) async -> Bool {
        save(name)
        guard let stack, !AssistantSampleClass.isActive, !writesHeld else {
            // No real classroom to write to now (or no account to write it
            // under): the name waits for the next chance on hers
            // (`AssistantBootstrapper.writeWaitingName`), or a rename would
            // never reach the guide's devices.
            ClassroomNames.markWaiting(as: .assistant)
            return true
        }
        let saved = await setInList(name, in: stack.viewContext) { context, created in
            saveList(context, created: created, container: stack.container)
        }
        if !saved { ClassroomNames.markWaiting(as: .assistant) }
        return saved
    }

    /// Sets her row in the classroom's list (`ClassroomNames.setMyName`) and
    /// saves it with `save`, passing a new row so it goes into the share.
    /// Before her record name is known the name waits instead, and nothing
    /// is saved; so too when her account changed while the list was being
    /// looked at, or `writesHeld` was set meanwhile, and when a newer name
    /// overtook this one. Tests pass their own save.
    @discardableResult
    static func setInList(
        _ name: String,
        in context: NSManagedObjectContext,
        save: (_ context: NSManagedObjectContext, _ created: [NSManagedObject]) -> Bool
    ) async -> Bool {
        guard let written = await ClassroomNames.setMyName(name, role: .assistant, in: context).written else {
            return true
        }
        guard written.isNew || written.person.hasChanges else { return true }
        return save(context, written.isNew ? [written.person] : [])
    }

    /// At launch once her record name has been asked for, after joining,
    /// after leaving the Sample Class and on coming back to the app: a name
    /// she gave before it was known (or before the classroom's list of names
    /// existed, or where it couldn't go in) joins the list, into the share
    /// (`ClassroomNames.writeWaitingName`). Never for the Debug launch's
    /// sample class, whose stack `stack` is then.
    static func writeWaitingName(on stack: CoreDataStack) async {
        guard !AssistantSampleClass.isRequested else { return }
        await writeWaitingName(in: stack.viewContext, container: stack.container)
    }

    /// `writeWaitingName(on:)`'s work; tests pass no container (no share).
    /// Nothing while `writesHeld`, checked again after the zone lookup
    /// (`ClassroomNames.mayStillWrite`).
    @discardableResult
    static func writeWaitingName(
        in context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer?
    ) async -> Bool {
        guard !writesHeld else { return false }
        return await ClassroomNames.writeWaitingName(role: .assistant, in: context) { context, created in
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

    /// Another Apple Account signed in on this iPhone: the name kept here
    /// was the last account's. Hers comes from the new account's iCloud copy
    /// when it has one (`restoreIfNeeded`), or she's asked again. Nothing in
    /// the classroom's list changes: the last account's row stays its own.
    static func forgetForNewAccount() {
        ClassroomIdentity.displayName = nil
        restoreIfNeeded()
    }

    /// Whether the account CloudKit now names is another one than before.
    /// Not when either is unknown: an account that couldn't be read is no
    /// reason to ask her name again.
    nonisolated static func isAnotherAccount(before: String?, now: String?) -> Bool {
        guard let before = ClassroomIdentity.realRecordName(before),
              let now = ClassroomIdentity.realRecordName(now) else { return false }
        return before != now
    }
}
