// swiftlint:disable file_length
// ClassroomNames.swift
// The classroom's shared list of names: each person sets their own, and every
// screen looks names up when it words a line, so a rename reaches old entries.

import CloudKit
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
///   the survivor every device agrees on, carrying the newest name over; a row
///   already in the classroom's share zone goes first, and rows in another
///   classroom's zone are never theirs to fold. At launch nothing is folded
///   until the class has arrived (`Arrival`), so a stale name never goes up
///   over a rename still on its way down.
/// - **Clearing keeps the row.** A cleared name is stored empty; deleting the
///   row would let another device's older one bring the old name back.
/// - **Display only.** Names are what people typed, shown as typed; nothing is
///   stamped with them. Apple's name for the share's owner is never stored.
/// - **Never ask iCloud on the main thread.** Which zone a row is in is asked
///   of CloudKit in one batch off the main thread (`ClassroomNames+Zones`):
///   the question waits on the mirroring delegate, and on the main thread it
///   froze the app until iOS killed it (2026-10-06). The writes wait for the
///   answer, one at a time, then check the account again and fetch the rows
///   afresh; the reads use the zones last looked up (`knownZones`).
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

    /// What `setMyName` did.
    enum NameSet {
        /// The person's row was updated or made; the caller saves.
        case written(Written)
        /// No row, and the name is empty: nothing to clear, and nothing waits.
        case nothingToClear
        /// Nothing written yet: the name waits on this device, and
        /// `writeWaitingName` writes it later (on the notebook, after the next
        /// import). This account's record name isn't known yet, CloudKit
        /// didn't say where the rows are in time, or this device may not
        /// write now (the account is being read again, or the stores are gone).
        case waiting
        /// Not saved: another Apple Account signed in during the wait, so the
        /// name, typed under the last one, was taken back, and nothing waits
        /// for the new one. The caller says it wasn't saved (2026-10-09 hunt, #5).
        case nothing
        /// A newer `setMyName` came while this one waited: it wrote nothing,
        /// and the newer one writes. The caller doesn't save.
        case overtaken

        var written: Written? {
            if case .written(let written) = self { return written }
            return nil
        }
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
    ///
    /// Waits for the zone lookup (`lookUpMyZones`), one write at a time. The
    /// name is marked waiting before the wait, so one typed just before the
    /// app is suspended or quit is written at the next launch. If this
    /// device may not write now (the account is being read again, the stores
    /// are gone, or CloudKit didn't answer in time) it keeps waiting, and on
    /// the notebook is written after the next import (`holdWaitingName`). An
    /// account being read again may turn out to be the same one; a waiting
    /// name is dropped only once another is confirmed
    /// (`forgetWaitingName`, the Assistant's `forgetForNewAccount`). If
    /// another account is known to have signed in meanwhile, the mark is
    /// taken back and nothing is written, so the last account's name never
    /// goes into the new one's row (2026-10-09 hunt, #5). If a newer call
    /// came, this one writes nothing.
    @discardableResult
    static func setMyName(
        _ name: String?,
        role: CDClassroomMembership.ClassroomRole,
        now: Date = Date(),
        in context: NSManagedObjectContext,
        arrival: Arrival = .shared
    ) async -> NameSet {
        let typed = name?.trimmed() ?? ""
        guard let me = ClassroomIdentity.currentUserRecordName else {
            ClassroomIdentity.displayName = typed
            mark(waitingAs: role, typedUnder: nil)
            return .waiting
        }
        nameSets += 1
        let call = nameSets
        if beforeMarks == nil { beforeMarks = .now }
        defer { if call == nameSets { beforeMarks = nil } }
        ClassroomIdentity.displayName = typed
        mark(waitingAs: role, typedUnder: me)
        await gate.enter()
        defer { gate.leave() }
        guard call == nameSets else { return .overtaken }
        guard let zones = await lookUpMyZones(me, role: role, in: context) else {
            guard call == nameSets else { return .overtaken }
            if let now = ClassroomIdentity.currentUserRecordName, now != me {
                unmark(typed, as: role)
                return .nothing
            }
            holdWaitingName(for: me, in: context, arrival: arrival)
            return .waiting
        }
        guard call == nameSets else { return .overtaken }
        let written = upsert(typed, recordName: me, role: role, now: now, zones: zones, in: context)
        stopWaiting(as: role, keeping: typed)
        return written.map(NameSet.written) ?? .nothingToClear
    }

    /// Writes a name typed before this account's record name was known, and
    /// folds this person's duplicate rows. Run it once the record name has been
    /// asked for (after `ClassroomIdentity.refreshRecordName()`), with the view
    /// context. A no-op while the record name is still unknown, or when nothing
    /// waits and nothing needs folding.
    ///
    /// Nothing is written or folded until the class is on this device
    /// (`Arrival.classIsHere`): a classroom membership, and this launch's first
    /// successful import into the store this person's rows live in since that
    /// membership was pinned. Before then a fold could send an older name over
    /// a rename still on its way down, and her row was written where no class
    /// could take it. Until then the write waits, and runs again after the
    /// next import.
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
    ///
    /// Waits for the zone lookup (`lookUpMyZones`), one write at a time; then
    /// writes nothing if the account changed meanwhile. A call that comes while
    /// one runs on the same context asks for one more run afterwards, with the
    /// latest call's arguments, and returns what that run returns.
    @discardableResult
    static func writeWaitingName(
        role: CDClassroomMembership.ClassroomRole? = nil,
        now: Date = Date(),
        in context: NSManagedObjectContext,
        arrival: Arrival = .shared,
        save: @escaping (_ context: NSManagedObjectContext, _ created: [NSManagedObject]) -> Bool = { context, _ in
            context.safeSave()
        }
    ) async -> Bool {
        let write = WaitingWrite(role: role, now: now, context: context, arrival: arrival, save: save)
        return await runCoalesced(write) { await writeWaitingNameOnce($0) }
    }

    /// One run of `writeWaitingName`.
    private static func writeWaitingNameOnce(_ write: WaitingWrite) async -> Bool {
        let context = write.context
        guard let me = ClassroomIdentity.currentUserRecordName,
              context.persistentStoreCoordinator?.persistentStores.isEmpty == false else { return false }
        dropWaitingName(typedUnderAnotherThan: me)
        let deviceRole = write.role ?? CDClassroomMembership.currentRole(in: context)
        write.arrival.start()
        guard write.arrival.classIsHere(role: deviceRole, in: context) else {
            holdUntilNextImport(write, for: me)
            return false
        }
        await gate.enter()
        defer { gate.leave() }
        // The zones of the rows this run writes: a waiting name's role can
        // name the other store (a notebook that joined a class as an
        // assistant, with his guide's name waiting).
        let lookupRole = ClassroomIdentity.nameWaitingAs ?? deviceRole
        guard let zones = await lookUpMyZones(me, role: lookupRole, in: context) else {
            // CloudKit didn't say in time (2026-10-09 hunt, #7): try again
            // after the next import rather than wait for the next launch.
            if mayStillWrite(as: me), context.persistentStoreCoordinator?.persistentStores.isEmpty == false {
                holdUntilNextImport(write, for: me)
            }
            return false
        }
        refreshUnchangedRows(in: context)
        let waitingRole = waitingRole(me, deviceRole: deviceRole, zones: zones, in: context)
        // What waits changed during the lookup: the next run asks again.
        guard (waitingRole ?? deviceRole) == lookupRole else { return false }

        var created: [NSManagedObject] = []
        if let waitingRole {
            let typed = ClassroomIdentity.displayName ?? ""
            let written = upsert(typed, recordName: me, role: waitingRole, now: write.now, zones: zones, in: context)
            if let written, written.isNew {
                created.append(written.person)
            }
        } else {
            foldCounting(myRows(me, role: deviceRole, zones: zones, in: context), zones: zones, in: context)
        }
        // Save only for a change to the list, never for something else the
        // view context happens to be holding.
        let pending = context.insertedObjects.union(context.updatedObjects).union(context.deletedObjects)
        let listChanged = pending.contains { $0 is CDClassroomPerson }
        if listChanged, !write.save(context, created) { return false }
        if let waitingRole { stopWaiting(as: waitingRole, keeping: ClassroomIdentity.displayName ?? "") }
        return listChanged
    }

    /// The role a waiting name goes in as, or nil when none waits. An
    /// assistant who named herself before the list existed has a name on her
    /// phone and no row; that counts as waiting too.
    private static func waitingRole(
        _ me: String,
        deviceRole: CDClassroomMembership.ClassroomRole,
        zones: ZoneMap,
        in context: NSManagedObjectContext
    ) -> CDClassroomMembership.ClassroomRole? {
        if let waiting = ClassroomIdentity.nameWaitingAs { return waiting }
        guard deviceRole == .assistant, ClassroomIdentity.displayName != nil,
              myRows(me, role: deviceRole, zones: zones, in: context).isEmpty else { return nil }
        return .assistant
    }

    /// What this person's own name field starts with: a name still waiting for
    /// the record name, else their row's (the same on all their devices, not
    /// this device's own copy), else the name on this device, else empty.
    /// Never asks iCloud: it reads the zones last looked up (`knownZones`).
    static func myName(role: CDClassroomMembership.ClassroomRole, in context: NSManagedObjectContext) -> String {
        if ClassroomIdentity.nameWaitingAs == nil, let me = ClassroomIdentity.currentUserRecordName,
           let row = myRows(me, role: role, zones: knownZones, countingUnanswered: true, in: context)
            .min(by: isNewer) {
            return row.displayName.trimmed()
        }
        return ClassroomIdentity.displayName ?? ""
    }

    /// Folds this person's own rows (two of their devices each wrote one) into
    /// the oldest by (`createdAt`, `id`), carrying the newest name over, so
    /// every device keeps the same row. Only the row's owner runs it; others'
    /// rows are never touched. Returns how many rows went. The caller saves.
    /// Waits for the zone lookup, one write at a time; nothing when the
    /// account changed meanwhile.
    @discardableResult
    static func foldMyRows(role: CDClassroomMembership.ClassroomRole, in context: NSManagedObjectContext) async -> Int {
        guard let me = ClassroomIdentity.currentUserRecordName else { return 0 }
        await gate.enter()
        defer { gate.leave() }
        guard let zones = await lookUpMyZones(me, role: role, in: context) else { return 0 }
        return foldCounting(myRows(me, role: role, zones: zones, in: context), zones: zones, in: context).deleted
    }

    // MARK: - Reading

    /// Everyone's current name, read once for a screen and handed to its
    /// wording (`RestockAuthor`, `AttendanceRules.markerName`,
    /// `AttendanceEmailLog.Send.senderName`), so a list isn't read per row.
    /// Never asks iCloud: it reads the zones last looked up (`knownZones`).
    static func snapshot(in context: NSManagedObjectContext) -> Snapshot {
        let request = CDFetchRequest(CDClassroomPerson.self)
        scopeToClassroom(request, in: context)
        var newest: [String: CDClassroomPerson] = [:]
        for row in context.safeFetch(request) {
            guard let id = ClassroomIdentity.realRecordName(row.recordName) else { continue }
            if let kept = newest[id], !isNewer(row, kept) { continue }
            newest[id] = row
        }
        // The classroom's owner, when known, and only the owner: a store can
        // still hold a guide's row from another class (one she was in before),
        // and an owner who hasn't named himself yet must not read as that
        // guide. Not known, the newest guide's row in the pinned classroom.
        let guide: CDClassroomPerson?
        if let owner = ownerRecordName(in: context) {
            guide = newest[owner]
        } else {
            let guides = newest.values.filter { $0.role == .leadGuide }
            guide = inPinnedClassroom(guides, zones: knownZones, in: context).min(by: isNewer)
        }
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
    private static func upsert( // swiftlint:disable:this function_parameter_count
        _ typed: String,
        recordName: String,
        role: CDClassroomMembership.ClassroomRole,
        now: Date,
        zones: ZoneMap,
        in context: NSManagedObjectContext
    ) -> Written? {
        let rows = myRows(recordName, role: role, zones: zones, in: context)
        if let row = foldCounting(rows, zones: zones, in: context).kept {
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

    /// The name is in the list now: nothing waits. The guide's own copy on the
    /// device goes too, since his stamps never carry a name and his row is the
    /// truth; an assistant keeps hers, which her marks are stamped with.
    private static func stopWaiting(as role: CDClassroomMembership.ClassroomRole, keeping typed: String) {
        ClassroomIdentity.nameWaitingAs = nil
        ClassroomIdentity.displayName = role == .assistant ? typed : nil
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
