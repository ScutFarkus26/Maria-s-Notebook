// ClassroomNames.swift
// The classroom's shared list of names: each person sets their own, and every
// screen looks names up when it words a line, so a rename reaches old entries.

import CoreData
import Foundation

/// The names people in the classroom go by, one `CDClassroomPerson` row each,
/// in the classroom share (schema 16). The only reader and writer of that type.
///
/// - **Your own row only.** Each person writes the row keyed by their own
///   CloudKit record name (`ClassroomIdentity.currentUserRecordName`), never
///   anyone else's. Before that name is known, what they type waits on the
///   device (`ClassroomIdentity.displayName`) and `writeWaitingName` writes it
///   once `ClassroomIdentity.refreshRecordName()` has answered.
/// - **Where rows go.** By role, as Restock's do (`RestockService.destinationStore`):
///   the guide's into the private store, which `SharedStoreOrphanGuard` shares
///   from, and it watches only view-context saves, so every write here is saved
///   on the view context; an assistant's straight into the shared store, then
///   into the share through `AssistantSave`, as her marks go.
/// - **Newest wins.** Two of the guide's devices can each write a row before the
///   other's arrives, so reads take the newest `modifiedAt` per record name. The
///   owner folds their own duplicates into the oldest by (`createdAt`, `id`),
///   the survivor every device agrees on, carrying the newest name over.
/// - **Clearing keeps the row.** A cleared name is stored empty; deleting the
///   row would let another device's older one bring the old name back.
/// - **Display only.** Names are what people typed, shown as typed; nothing is
///   stamped with them. Apple's name for the share's owner is never stored.
///
/// Reads come from the store the screen reads: in the Daybook Assistant, only
/// the classroom share (the shared store), as `AttendanceEmailLog` reads.
enum ClassroomNames {

    /// What `setMyName` wrote: the person's row, and whether it's new. The
    /// Assistant passes a new row to `AssistantSave` so it goes into the
    /// classroom share; the guide's joins from the private store by itself.
    struct Written {
        let person: CDClassroomPerson
        let isNew: Bool
    }

    // MARK: - Your own name

    /// Sets this person's own name in the classroom's list: their row, found by
    /// record name, is updated, or made when there's none. An empty name is
    /// stored empty (with no row yet there's nothing to clear, and nil comes
    /// back). Their duplicate rows are folded first (`foldMyRows`).
    ///
    /// Before this account's record name is known the name waits in
    /// `ClassroomIdentity.displayName`, nil comes back, and `writeWaitingName`
    /// writes it later. An assistant's name is kept there anyway: her own marks
    /// are stamped with it.
    ///
    /// The caller saves, on the view context: the guide's new row reaches the
    /// share only through `SharedStoreOrphanGuard`, which sees nothing else. On
    /// her phone the caller saves through `AssistantSave`, passing a new row.
    @discardableResult
    static func setMyName(
        _ name: String?,
        role: CDClassroomMembership.ClassroomRole,
        now: Date = Date(),
        in context: NSManagedObjectContext
    ) -> Written? {
        let typed = name?.trimmed() ?? ""
        guard let me = ClassroomIdentity.currentUserRecordName else {
            ClassroomIdentity.displayName = typed
            ClassroomIdentity.nameWaitingAs = role
            return nil
        }
        let written = upsert(typed, recordName: me, role: role, now: now, in: context)
        stopWaiting(as: role, keeping: typed)
        return written
    }

    /// Writes a name typed before this account's record name was known, and
    /// folds this person's duplicate rows. Run it once the record name has been
    /// asked for (after `ClassroomIdentity.refreshRecordName()`), with the view
    /// context. A no-op while the record name is still unknown, or when nothing
    /// waits and nothing needs folding.
    ///
    /// An assistant who named herself before the list existed has a name on her
    /// phone and no row; that counts as waiting too, so her name joins the list
    /// without her typing it again.
    ///
    /// Saves through `save` (`safeSave` unless given), passing what the write
    /// created: the Assistant passes `AssistantSave`, which puts a new row into
    /// the share. `role` is this device's (the Assistant passes `.assistant`); a
    /// waiting name keeps the role it was typed as. Returns whether it saved
    /// anything; after a failed save the name keeps waiting for the next launch.
    @discardableResult
    static func writeWaitingName(
        role: CDClassroomMembership.ClassroomRole? = nil,
        now: Date = Date(),
        in context: NSManagedObjectContext,
        save: (_ context: NSManagedObjectContext, _ created: [NSManagedObject]) -> Bool = { context, _ in
            context.safeSave()
        }
    ) -> Bool {
        guard let me = ClassroomIdentity.currentUserRecordName else { return false }
        let deviceRole = role ?? CDClassroomMembership.currentRole(in: context)
        var waitingRole = ClassroomIdentity.nameWaitingAs
        if waitingRole == nil, deviceRole == .assistant, ClassroomIdentity.displayName != nil,
           myRows(me, role: deviceRole, in: context).isEmpty {
            waitingRole = .assistant
        }

        var created: [NSManagedObject] = []
        if let waitingRole {
            let typed = ClassroomIdentity.displayName ?? ""
            if let written = upsert(typed, recordName: me, role: waitingRole, now: now, in: context), written.isNew {
                created.append(written.person)
            }
        } else {
            foldMyRows(role: deviceRole, in: context)
        }
        // Save only for a change to the list, never for something else the
        // view context happens to be holding.
        let pending = context.insertedObjects.union(context.updatedObjects).union(context.deletedObjects)
        guard pending.contains(where: { $0 is CDClassroomPerson }) else {
            if let waitingRole { stopWaiting(as: waitingRole, keeping: ClassroomIdentity.displayName ?? "") }
            return false
        }
        guard save(context, created) else { return false }
        if let waitingRole { stopWaiting(as: waitingRole, keeping: ClassroomIdentity.displayName ?? "") }
        return true
    }

    /// What this person's own name field starts with: a name still waiting for
    /// the record name, else their row's (the same on all their devices, not
    /// this device's own copy), else the name on this device, else empty.
    static func myName(role: CDClassroomMembership.ClassroomRole, in context: NSManagedObjectContext) -> String {
        if ClassroomIdentity.nameWaitingAs == nil, let me = ClassroomIdentity.currentUserRecordName,
           let row = myRows(me, role: role, in: context).min(by: isNewer) {
            return row.displayName.trimmed()
        }
        return ClassroomIdentity.displayName ?? ""
    }

    /// Folds this person's own rows (two of their devices each wrote one) into
    /// the oldest by (`createdAt`, `id`), carrying the newest name over, so
    /// every device keeps the same row. Only the row's owner runs it; others'
    /// rows are never touched. Returns how many rows went. The caller saves.
    @discardableResult
    static func foldMyRows(role: CDClassroomMembership.ClassroomRole, in context: NSManagedObjectContext) -> Int {
        guard let me = ClassroomIdentity.currentUserRecordName else { return 0 }
        let rows = myRows(me, role: role, in: context)
        fold(rows, in: context)
        return max(0, rows.count - 1)
    }

    // MARK: - Reading

    /// Everyone's current name, read once for a screen and handed to its
    /// wording (`RestockAuthor`, `AttendanceRules.markerName`,
    /// `AttendanceEmailLog.Send.senderName`), so a list isn't read per row.
    static func snapshot(in context: NSManagedObjectContext) -> Snapshot {
        let request = CDFetchRequest(CDClassroomPerson.self)
        scopeToClassroom(request, in: context)
        var newest: [String: CDClassroomPerson] = [:]
        for row in context.safeFetch(request) {
            guard let id = ClassroomIdentity.realRecordName(row.recordName) else { continue }
            if let kept = newest[id], !isNewer(row, kept) { continue }
            newest[id] = row
        }
        let guide = newest.values.filter { $0.role == .leadGuide }.min(by: isNewer)
        let guideName = guide.map { $0.displayName.trimmed() }.flatMap { $0.isEmpty ? nil : $0 }
        return Snapshot(
            names: newest.mapValues { $0.displayName.trimmed() },
            roles: newest.mapValues(\.role),
            guideName: guideName
        )
    }

    /// The name the person with `recordName` goes by now, or nil when they've
    /// given none (or cleared it).
    static func name(forRecordName recordName: String?, in context: NSManagedObjectContext) -> String? {
        guard let id = ClassroomIdentity.realRecordName(recordName) else { return nil }
        let request = CDFetchRequest(CDClassroomPerson.self)
        request.predicate = NSPredicate(format: "recordName == %@", id)
        scopeToClassroom(request, in: context)
        let name = context.safeFetch(request).min(by: isNewer)?.displayName.trimmed() ?? ""
        return name.isEmpty ? nil : name
    }

    /// The name the lead guide typed, or nil when he gave none.
    static func guideName(in context: NSManagedObjectContext) -> String? {
        snapshot(in: context).guideName
    }

    // MARK: - The snapshot

    /// Everyone's current name as one screen read it, passed into its wording
    /// so lines can name people without a fetch per row. Display only.
    nonisolated struct Snapshot: Sendable, Equatable {
        /// Each person's name by CloudKit record name, from their newest row,
        /// as typed (empty when they cleared it).
        var names: [String: String]
        /// Each person's role by record name, from the same row.
        var roles: [String: CDClassroomMembership.ClassroomRole]
        /// The name the lead guide typed, or nil when he gave none. A screen
        /// on her phone falls back to Apple's name for the share's owner with
        /// `fallingBack(toGuideName:)`.
        var guideName: String?

        init(
            names: [String: String] = [:],
            roles: [String: CDClassroomMembership.ClassroomRole] = [:],
            guideName: String? = nil
        ) {
            self.names = names
            self.roles = roles
            self.guideName = guideName
        }

        /// The name `recordName` goes by now, or nil when that person gave
        /// none, cleared it, or isn't in the list (a stand-in names nobody).
        func name(forRecordName recordName: String?) -> String? {
            guard let id = ClassroomIdentity.realRecordName(recordName),
                  let name = names[id]?.trimmed(), !name.isEmpty else { return nil }
            return name
        }

        /// The role `recordName`'s row gives, or nil when it isn't in the list.
        func role(forRecordName recordName: String?) -> CDClassroomMembership.ClassroomRole? {
            ClassroomIdentity.realRecordName(recordName).flatMap { roles[$0] }
        }

        /// This snapshot with `appleName` (CloudKit's name for the share's
        /// owner, shown but never stored) as the guide's name when he typed none.
        func fallingBack(toGuideName appleName: String?) -> Snapshot {
            var copy = self
            if copy.guideName == nil, let appleName = appleName?.trimmed(), !appleName.isEmpty {
                copy.guideName = appleName
            }
            return copy
        }
    }

    // MARK: - Rows

    /// Updates this person's row (after folding duplicates) or makes one.
    private static func upsert(
        _ typed: String,
        recordName: String,
        role: CDClassroomMembership.ClassroomRole,
        now: Date,
        in context: NSManagedObjectContext
    ) -> Written? {
        if let row = fold(myRows(recordName, role: role, in: context), in: context) {
            if row.displayName != typed || row.role != role {
                row.displayName = typed
                row.role = role
                row.modifiedAt = now
            }
            return Written(person: row, isNew: false)
        }
        guard !typed.isEmpty else { return nil }
        let row = CDClassroomPerson(context: context)
        if let store = RestockService.destinationStore(for: role, in: context) { context.assign(row, to: store) }
        row.recordName = recordName
        row.role = role
        row.displayName = typed
        row.createdAt = now
        row.modifiedAt = now
        return Written(person: row, isNew: true)
    }

    /// Keeps the survivor of `rows`, with the newest name, and deletes the
    /// rest. Returns the survivor, or nil when there are no rows.
    @discardableResult
    private static func fold(_ rows: [CDClassroomPerson], in context: NSManagedObjectContext) -> CDClassroomPerson? {
        guard let kept = rows.min(by: isOlder) else { return nil }
        guard rows.count > 1, let newest = rows.min(by: isNewer) else { return kept }
        if newest !== kept {
            kept.displayName = newest.displayName
            kept.roleRaw = newest.roleRaw
            kept.modifiedAt = newest.modifiedAt
        }
        for row in rows where row !== kept { context.delete(row) }
        return kept
    }

    /// The name is in the list now: nothing waits. The guide's own copy on the
    /// device goes too, since his stamps never carry a name and his row is the
    /// truth; an assistant keeps hers, which her marks are stamped with.
    private static func stopWaiting(as role: CDClassroomMembership.ClassroomRole, keeping typed: String) {
        ClassroomIdentity.nameWaitingAs = nil
        ClassroomIdentity.displayName = role == .assistant ? typed : nil
    }

    /// This person's own rows, in the store their role writes to (the guide's
    /// private store, an assistant's shared store; everything with one store).
    /// Never the other store: there a row with the same record name belongs to
    /// another classroom this account is in.
    private static func myRows(
        _ recordName: String,
        role: CDClassroomMembership.ClassroomRole,
        in context: NSManagedObjectContext
    ) -> [CDClassroomPerson] {
        let request = CDFetchRequest(CDClassroomPerson.self)
        request.predicate = NSPredicate(format: "recordName == %@", recordName)
        if let store = RestockService.destinationStore(for: role, in: context) { request.affectedStores = [store] }
        return context.safeFetch(request)
    }

    /// Oldest first by (`createdAt`, `id`): the row every device keeps.
    static func isOlder(_ lhs: CDClassroomPerson, _ rhs: CDClassroomPerson) -> Bool {
        let left = lhs.createdAt ?? .distantPast
        let right = rhs.createdAt ?? .distantPast
        if left != right { return left < right }
        return (lhs.id?.uuidString ?? "") < (rhs.id?.uuidString ?? "")
    }

    /// Newest first by `modifiedAt`, then by `id`: the same order on every device.
    static func isNewer(_ lhs: CDClassroomPerson, _ rhs: CDClassroomPerson) -> Bool {
        let left = lhs.modifiedAt ?? .distantPast
        let right = rhs.modifiedAt ?? .distantPast
        if left != right { return left > right }
        return (lhs.id?.uuidString ?? "") > (rhs.id?.uuidString ?? "")
    }

    /// In the Assistant, reads only the classroom share (the shared store), as
    /// `AttendanceEmailLog` does: on an Apple Account that also keeps a notebook
    /// of its own, the private store holds that notebook's names. The notebook
    /// reads both stores (the guide's classroom lives in his private store); a
    /// single store reads everything.
    private static func scopeToClassroom<T>(_ request: NSFetchRequest<T>, in context: NSManagedObjectContext) {
        #if ASSISTANT_APP
        let shared = context.persistentStoreCoordinator?.persistentStores.first {
            $0.configurationName == CoreDataStack.sharedConfiguration
        }
        if let shared { request.affectedStores = [shared] }
        #endif
    }
}
