// ClassroomNames+Zones.swift
// Where each name row is mirrored in CloudKit, asked off the main thread.
// The question waits on the mirroring delegate, which answers after its sync
// work; asked on the main thread as an import finished, it froze the app until
// iOS killed it (2026-10-06, three times on Danny's iPhone).

import CloudKit
import CoreData
import Foundation
import OSLog

extension ClassroomNames {

    // MARK: - The zone map

    /// What a zone lookup said about one row.
    nonisolated enum ZoneAnswer: Sendable, Equatable {
        /// Mirrored to this CloudKit zone.
        case zone(String)
        /// Never sent to iCloud: a temporary ID, no record for it yet, or no
        /// CloudKit at all (one store, unit tests). Only this device has it.
        case notSent
        /// Not asked about: the row appeared after the lookup began.
        case noAnswer
    }

    /// Where rows live, as one lookup answered.
    nonisolated struct ZoneMap: Sendable {
        /// The rows asked about.
        var asked: Set<NSManagedObjectID> = []
        /// The zone of each asked row that has a record.
        var zones: [NSManagedObjectID: String] = [:]
        /// False when there is no CloudKit container: nothing is ever sent.
        var syncs = true

        func answer(for objectID: NSManagedObjectID) -> ZoneAnswer {
            if objectID.isTemporaryID || !syncs { return .notSent }
            guard asked.contains(objectID) else { return .noAnswer }
            return zones[objectID].map(ZoneAnswer.zone) ?? .notSent
        }

        /// This map with `newer`'s answers over its own.
        mutating func update(with newer: ZoneMap) {
            for id in newer.asked { zones[id] = newer.zones[id] }
            asked.formUnion(newer.asked)
            syncs = newer.syncs
        }
    }

    /// Where the rows live as last looked up, for the reads (`snapshot`,
    /// `myName`), which never ask iCloud themselves. Warmed by `warmZones`
    /// and kept current by every write's lookup. A row it has no answer for
    /// counts as in the pinned classroom, as a row not yet sent does.
    private(set) static var knownZones = ZoneMap()

    /// Warms `knownZones` from every name row `context`'s stores hold (a small
    /// table), asking off the main thread. Run once the stores load, after
    /// each successful import (`Arrival`, which this tells to), and after the
    /// Assistant builds a new stack (new stores, new object IDs).
    static func warmZones(in context: NSManagedObjectContext, arrival: Arrival? = .shared) async {
        arrival?.zonesContext = context
        await gate.enter()
        defer { gate.leave() }
        let request = CDFetchRequest(CDClassroomPerson.self)
        request.includesPropertyValues = false
        let ids = context.safeFetch(request).map(\.objectID)
        knownZones = await lookUpZones(of: ids, in: context)
    }

    // MARK: - Rows and their zones

    /// Keeps the survivor of `rows`, with the newest name, and deletes the
    /// copies it safely can. Returns the survivor, or nil when there are no rows.
    ///
    /// The survivor is the oldest row by (`createdAt`, `id`) on every device,
    /// whatever each knows about zones: choosing it by zone let two devices
    /// with different views each keep a different row and delete the other's,
    /// and both deletes synced (2026-10-05 review). A copy is deleted only when
    /// it is in the survivor's zone, or has never been sent to iCloud (this
    /// device's own, so deleting it reaches no other device). A copy in
    /// another zone stays: on the guide's devices a row written before the pin
    /// arrived sits in his default zone until the orphan guard attaches it, and
    /// deleting the shared copy meanwhile took his name out of the assistants'
    /// list (#24). Reads take the newest copy, so the name shows either way.
    ///
    /// Where rows live comes from `zones`, looked up before the rows were
    /// fetched afresh. A copy the lookup has no answer for (it arrived during
    /// the wait) stays for the next run; when the survivor has none, only
    /// copies never sent go. Also says how many copies it deleted.
    @discardableResult
    static func foldCounting(
        _ rows: [CDClassroomPerson], zones: ZoneMap, in context: NSManagedObjectContext
    ) -> (kept: CDClassroomPerson?, deleted: Int) {
        guard let kept = rows.min(by: isOlder) else { return (nil, 0) }
        guard rows.count > 1, let newest = rows.min(by: isNewer) else { return (kept, 0) }
        if newest !== kept {
            kept.displayName = newest.displayName
            kept.roleRaw = newest.roleRaw
            kept.modifiedAt = newest.modifiedAt
        }
        let keptZone = zones.answer(for: kept.objectID)
        // A copy of the survivor itself (a restore beside the row CloudKit
        // brings back: same id, same createdAt) is never deleted. No order
        // tells two such copies apart the same way on every device, so each
        // device could keep a different one and delete the other, and the
        // name would vanish.
        var deleted = 0
        for row in rows where row !== kept && row.id != kept.id {
            switch zones.answer(for: row.objectID) {
            case .notSent: break
            case .zone(let zone): guard keptZone == .zone(zone) else { continue }
            case .noAnswer: continue
            }
            context.delete(row)
            deleted += 1
        }
        return (kept, deleted)
    }

    /// This person's own rows, in the store their role writes to (the guide's
    /// private store, an assistant's shared store; everything with one store).
    /// Never the other store: there a row with the same record name belongs to
    /// another classroom this account is in. Nor, in that store, another share
    /// zone than the pinned classroom's: an assistant's shared store can hold
    /// a classroom she was in before, and folding there deleted her row in it
    /// (2026-10-05 hunt, #24). A row not yet sent to iCloud has no zone yet; it
    /// is this device's own. Where rows live comes from `zones`; rows deleted
    /// meanwhile (by an import merged during a wait) are left out.
    ///
    /// For the writes, a row `zones` has no answer for (it arrived during the
    /// wait) is left out too while a classroom is pinned: it may be an older
    /// copy in a previous classroom's zone, which the fold would keep and
    /// rename. The next run, with its answer, takes it in. The reads
    /// (`myName`) pass `countingUnanswered` and count it in.
    static func myRows(
        _ recordName: String,
        role: CDClassroomMembership.ClassroomRole,
        zones: ZoneMap,
        countingUnanswered: Bool = false,
        in context: NSManagedObjectContext
    ) -> [CDClassroomPerson] {
        let rows = fetchMyRows(recordName, role: role, in: context).filter {
            !$0.isDeleted && $0.managedObjectContext != nil
        }
        return inPinnedClassroom(rows, zones: zones, countingUnanswered: countingUnanswered, in: context)
    }

    /// Every row with `recordName` in the store `role` writes to, whatever
    /// its zone: what a write asks the zones of (`lookUpMyZones`).
    static func fetchMyRows(
        _ recordName: String,
        role: CDClassroomMembership.ClassroomRole,
        in context: NSManagedObjectContext
    ) -> [CDClassroomPerson] {
        let request = CDFetchRequest(CDClassroomPerson.self)
        request.predicate = NSPredicate(format: "recordName == %@", recordName)
        if let store = RestockService.destinationStore(for: role, in: context) { request.affectedStores = [store] }
        return context.safeFetch(request)
    }

    /// `rows` without those in another classroom's share zone: the pinned
    /// classroom's, and those in no share yet (not sent, or waiting in the
    /// guide's own zone to be filed). All of them when nothing is pinned. A
    /// row `zones` has no answer for counts as in the pinned classroom unless
    /// `countingUnanswered` is false (the writes, `myRows`).
    static func inPinnedClassroom(
        _ rows: [CDClassroomPerson],
        zones: ZoneMap,
        countingUnanswered: Bool = true,
        in context: NSManagedObjectContext
    ) -> [CDClassroomPerson] {
        guard !rows.isEmpty, let pinned = CDClassroomMembership.pinnedZoneName(in: context) else { return rows }
        return rows.filter { row in
            switch zones.answer(for: row.objectID) {
            case .zone(let zone): return !zone.hasPrefix(shareZonePrefix) || zone == pinned
            case .notSent: return true
            case .noAnswer: return countingUnanswered
            }
        }
    }

    /// `ClassroomShareScope.shareZonePrefix`, which the Daybook Assistant
    /// doesn't compile: the zones behind a `CKShare`.
    static let shareZonePrefix = "com.apple.coredata.cloudkit.share."

    // MARK: - Asking

    /// Test seam: the zones of a batch of rows, instead of asking CloudKit.
    /// A row with no entry has no record (not sent).
    @TaskLocal static var zoneLookupOverride: (@Sendable ([NSManagedObjectID]) -> [NSManagedObjectID: String])?

    /// Test seam: runs once each lookup has its answer, still inside the
    /// wait, so a test can change things the way an import or a second tap
    /// would while the lookup is out.
    @TaskLocal static var zoneLookupHook: LookupHook?

    /// What `zoneLookupHook` runs, on the main actor.
    final class LookupHook {
        let during: () async -> Void

        init(_ during: @escaping () async -> Void) {
            self.during = during
        }
    }

    private static let zonesLogger = Logger.app(category: "names")

    /// Where each of `ids` lives, waiting for CloudKit off the main thread.
    /// Run it holding `gate`.
    static func lookUpZones(of ids: [NSManagedObjectID], in context: NSManagedObjectContext) async -> ZoneMap {
        let permanent = ids.filter { !$0.isTemporaryID }
        var map = ZoneMap(asked: Set(permanent))
        if let zoneLookupOverride {
            map.zones = zoneLookupOverride(permanent)
        } else if let container = CoreDataStack.cloudKitContainer(for: context) {
            let started = ContinuousClock.now
            map.zones = await recordZoneNames(of: permanent, container: container)
            let waited = String(describing: ContinuousClock.now - started)
            zonesLogger.debug("Name rows' zones: \(permanent.count) rows in \(waited, privacy: .public)")
        } else {
            map.syncs = false
        }
        if let zoneLookupHook { await zoneLookupHook.during() }
        return map
    }

    /// The CloudKit zone each of `ids` is mirrored to, asked in one batch off
    /// the caller's actor: `recordIDs(for:)` waits on the mirroring delegate.
    /// A row with no record has no entry. The only place the name list asks
    /// CloudKit where its rows are; one at a time (`gate`), so at most one
    /// pool thread waits here.
    @concurrent
    nonisolated static func recordZoneNames(
        of ids: [NSManagedObjectID],
        container: NSPersistentCloudKitContainer
    ) async -> [NSManagedObjectID: String] {
        guard !ids.isEmpty else { return [:] }
        return container.recordIDs(for: ids).mapValues(\.zoneID.zoneName)
    }

    /// The first steps of every write, holding `gate`: this person's rows'
    /// IDs are collected, their zones asked off the main thread, and then
    /// whether this device may still write as `me` is checked again, and
    /// whether `context` still has its stores (her stack can be rebuilt
    /// during the wait). Nil when it may not. The caller refetches the rows
    /// (`myRows`): an import can delete or change them during the wait.
    static func lookUpMyZones(
        _ me: String,
        role: CDClassroomMembership.ClassroomRole,
        in context: NSManagedObjectContext
    ) async -> ZoneMap? {
        let ids = fetchMyRows(me, role: role, in: context).map(\.objectID)
        let map = await lookUpZones(of: ids, in: context)
        guard mayStillWrite(as: me),
              context.persistentStoreCoordinator?.persistentStores.isEmpty == false else { return nil }
        knownZones.update(with: map)
        return map
    }

    /// After a wait: whether this device still writes as `me`. Not when
    /// another account signed in meanwhile, nor on her phone while an account
    /// change is being read (`AssistantNameStore.writesHeld`); the next
    /// trigger writes under the new account.
    static func mayStillWrite(as me: String) -> Bool {
        guard ClassroomIdentity.currentUserRecordName == me else { return false }
        #if ASSISTANT_APP
        if AssistantNameStore.writesHeld { return false }
        #endif
        return true
    }

    // MARK: - One write at a time

    /// One name-list lookup or write at a time, in arrival order: the writes
    /// now wait for CloudKit, so a second trigger (an import, a return to the
    /// app, a second quick save) could otherwise run over the first.
    final class Gate {
        private var busy = false
        private var waiting: [CheckedContinuation<Void, Never>] = []

        func enter() async {
            guard busy else {
                busy = true
                return
            }
            await withCheckedContinuation { waiting.append($0) }
        }

        /// Hands the gate to the next in line, if any.
        func leave() {
            if waiting.isEmpty {
                busy = false
            } else {
                waiting.removeFirst().resume()
            }
        }
    }

    static let gate = Gate()

    /// How many `setMyName` calls have begun: one overtaken by a newer one
    /// before it wrote doesn't write.
    static var nameSets = 0

    /// This device's name and waiting mark before the first of the
    /// `setMyName` calls still running marked its name waiting: what an
    /// account change during their wait puts back.
    struct BeforeMarks {
        let name: String?
        let role: CDClassroomMembership.ClassroomRole?
    }

    static var beforeMarks: BeforeMarks?

    /// Another account signed in while `setMyName` waited: its mark (and
    /// those of the calls it overtook) goes back to what was there before,
    /// unless something else has changed it since (the Assistant's
    /// `forgetForNewAccount`).
    static func unmark(_ typed: String, as role: CDClassroomMembership.ClassroomRole) {
        guard let before = beforeMarks else { return }
        if ClassroomIdentity.nameWaitingAs == role { ClassroomIdentity.nameWaitingAs = before.role }
        if (ClassroomIdentity.displayName ?? "") == typed { ClassroomIdentity.displayName = before.name }
    }

    /// One `writeWaitingName` call's arguments.
    struct WaitingWrite {
        let role: CDClassroomMembership.ClassroomRole?
        let now: Date
        let context: NSManagedObjectContext
        let arrival: Arrival
        let save: (_ context: NSManagedObjectContext, _ created: [NSManagedObject]) -> Bool
    }

    /// The calls to `writeWaitingName` on one context that came while it ran:
    /// the latest one's arguments (her stack's closure goes stale after a
    /// rebuild), run once more afterwards, and the callers waiting for that run.
    final class Rerun {
        var write: WaitingWrite?
        var waiting: [CheckedContinuation<Bool, Never>] = []
    }

    /// The `writeWaitingName` running on each context, by context.
    static var reruns: [ObjectIdentifier: Rerun] = [:]

    /// Runs `write`, unless one is already running on its context: then it
    /// asks for one more run afterwards, with the latest call's arguments,
    /// and returns what that run returns.
    static func runCoalesced(_ write: WaitingWrite, _ run: (WaitingWrite) async -> Bool) async -> Bool {
        let key = ObjectIdentifier(write.context)
        if let rerun = reruns[key] {
            rerun.write = write
            return await withCheckedContinuation { rerun.waiting.append($0) }
        }
        let rerun = Rerun()
        reruns[key] = rerun
        defer { reruns[key] = nil }
        let wrote = await run(write)
        while let next = rerun.write {
            rerun.write = nil
            let waiting = rerun.waiting
            rerun.waiting = []
            let nextWrote = await run(next)
            for caller in waiting { caller.resume(returning: nextWrote) }
        }
        return wrote
    }
}
