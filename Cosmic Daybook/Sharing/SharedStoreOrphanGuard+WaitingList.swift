import Foundation
@preconcurrency import CoreData
import OSLog

// MARK: - The waiting list
//
// Records waiting for the classroom share, oldest first, persisted in
// UserDefaults: the URIs under `classroomSharePendingAttach` (as before
// 2026-10-05) and, beside them, when each was last added. A pass forgets only
// the entries it took as it found them, so a record added again while the
// pass ran (a returning student edited mid-pass, say) stays for the next one.
//
// The list is capped for a notebook that is never shared. Past `maxPending`
// a prune first takes out what can no longer go into the share — deleted
// since, already in a share, or (once the school-year start is known) outside
// this school year — and only then, while the classroom isn't shared, the
// oldest. Once it is shared (pinned) nothing is dropped for length; that is
// logged. The 2026-10-05 hunt found the old cap dropping a new device's
// unattached marks behind entries that were already shared.

extension SharedStoreOrphanGuard {

    private static var pendingKey: String { UserDefaultsKeys.classroomSharePendingAttach }
    private static var stampsKey: String { UserDefaultsKeys.classroomSharePendingAttachStamps }
    private static var pinSeenKey: String { UserDefaultsKeys.classroomSharePinSeen }
    private static var pinSeenAtKey: String { UserDefaultsKeys.classroomSharePinSeenAt }

    /// One record waiting, and when it was last added.
    struct Entry: Equatable, Sendable {
        let uri: String
        let stamp: TimeInterval
    }

    /// URIs of records waiting to be attached, oldest first.
    var pendingURIs: [String] {
        defaults.stringArray(forKey: Self.pendingKey) ?? []
    }

    /// The waiting list with each entry's stamp (0 for one listed before
    /// stamps were kept).
    var pendingEntries: [Entry] {
        let stamps = defaults.dictionary(forKey: Self.stampsKey) as? [String: TimeInterval] ?? [:]
        return pendingURIs.map { Entry(uri: $0, stamp: stamps[$0] ?? 0) }
    }

    func enqueue(_ ids: [NSManagedObjectID]) {
        add(ids.map { $0.uriRepresentation().absoluteString })
    }

    /// Adds `uris` at the end with a fresh stamp; one already waiting moves
    /// there. Never drops anything itself: past the cap a prune decides.
    func add(_ uris: [String]) {
        guard !uris.isEmpty else { return }
        let incoming = Set(uris)
        var entries = pendingEntries.filter { !incoming.contains($0.uri) }
        var seen = Set<String>()
        for uri in uris where seen.insert(uri).inserted {
            entries.append(Entry(uri: uri, stamp: nextStamp()))
        }
        write(entries)
        if entries.count > Self.maxPending { pruneSoon() }
    }

    private func nextStamp() -> TimeInterval {
        lastStamp = max(Date().timeIntervalSinceReferenceDate, lastStamp.nextUp)
        return lastStamp
    }

    private func write(_ entries: [Entry]) {
        guard !entries.isEmpty else {
            clearPending()
            return
        }
        defaults.set(entries.map(\.uri), forKey: Self.pendingKey)
        let stamps = Dictionary(entries.map { ($0.uri, $0.stamp) }, uniquingKeysWith: { _, last in last })
        defaults.set(stamps, forKey: Self.stampsKey)
    }

    /// Forgets the waiting list.
    func clearPending() {
        defaults.removeObject(forKey: Self.pendingKey)
        defaults.removeObject(forKey: Self.stampsKey)
    }

    /// Forgets `uris`, whenever they were added, and keeps the rest.
    func removePending(_ uris: [String]) {
        let done = Set(uris)
        write(pendingEntries.filter { !done.contains($0.uri) })
    }

    /// Forgets the entries a pass took (`taken`, as it found them), except
    /// those in `keeping` and any added again since (their stamp moved).
    func forget(_ taken: [Entry], except keeping: Set<String> = []) {
        write(Self.remaining(pendingEntries, after: taken, keeping: keeping))
    }

    /// `current` less the entries of `taken` still as they were taken, except
    /// those in `keeping`.
    static func remaining(_ current: [Entry], after taken: [Entry], keeping: Set<String>) -> [Entry] {
        let takenStamps = Dictionary(taken.map { ($0.uri, $0.stamp) }, uniquingKeysWith: { _, last in last })
        return current.filter { entry in
            guard let stamp = takenStamps[entry.uri], stamp == entry.stamp else { return true }
            return keeping.contains(entry.uri)
        }
    }

    // MARK: - A pin made on another device

    /// The first time this device sees a pin in a zone other than the one it
    /// noted last, the pin was made elsewhere (Set Up Classroom Sharing run on
    /// the guide's Mac, say), and it forgets what it listed before that pin
    /// was made. That setup took every classroom record it had, and
    /// this device's view of which are shared may still be half downloaded, so
    /// attaching them here could ask CloudKit to share records already in the
    /// share (2026-10-05 hunt). One that never reached the other device stays
    /// unshared, and Settings › Classroom counts it ("Add them to the share").
    /// Entries listed before stamps were kept (stamp 0) can't be dated, and
    /// stay. Setup on this device notes its own pin first (`notePinMadeHere`),
    /// so its list is never touched here.
    ///
    /// Either way the pin is noted as seen now (`pinSeenAt`), which holds
    /// filing until an import that began after it has finished
    /// (`waitingForImportAfterPin`).
    ///
    /// With no zone noted at all, nothing is forgotten: builds before
    /// 2026-10-06 never noted one, not even the pin setup made on this very
    /// device, and nothing else on the device says which made it (the
    /// membership row has no device, and the guide's Mac and iPad share one
    /// owner). Forgetting there dropped what setup had failed to attach on
    /// the guide's own Mac (bug hunt 2026-10-09, #3). The wait for an import
    /// still keeps a half-downloaded device from sharing records twice; on
    /// the pin's own device it costs only that wait.
    func forgetWhatSetupElsewhereTook(pinnedZone: String, pinnedAt: Date?) {
        let seenBefore = defaults.string(forKey: Self.pinSeenKey)
        guard seenBefore != pinnedZone else { return }
        defaults.set(pinnedZone, forKey: Self.pinSeenKey)
        defaults.set(Date().timeIntervalSinceReferenceDate, forKey: Self.pinSeenAtKey)
        guard seenBefore != nil else {
            Self.logger.notice("Classroom share pin noted for the first time: forgot nothing; waiting for an import")
            return
        }
        guard let pinnedAt else { return }
        let made = pinnedAt.timeIntervalSinceReferenceDate
        let entries = pendingEntries
        let kept = entries.filter { $0.stamp == 0 || $0.stamp >= made }
        guard kept.count < entries.count else { return }
        let forgotten = entries.count - kept.count
        Self.logger.notice(
            "Classroom share pinned on another device: forgot \(forgotten, privacy: .public) listed before it"
        )
        write(kept)
    }

    /// Set Up Classroom Sharing on this device just made the pin in `zone`
    /// (`createPinnedShare`): it is this device's own, and what it listed
    /// stays for setup and the guard to settle. Only for a pin made here, now:
    /// it ends the wait for an import (`waitingForImportAfterPin`).
    func notePinMadeHere(zone: String) {
        defaults.set(zone, forKey: Self.pinSeenKey)
        defaults.removeObject(forKey: Self.pinSeenAtKey)
    }

    /// For a path that files this device's existing records into the share
    /// outside the guard's passes (a resumed Set Up Classroom Sharing, "Add
    /// them to the share", the attendance catch-up): true while it must wait.
    /// A pin this device hasn't seen is noted first, as the guard's own passes
    /// note it (`forgetWhatSetupElsewhereTook`); then it waits as they do,
    /// until an import into the notebook that began after the pin was seen
    /// has finished. Before then this device may hold only part of what is
    /// shared, and `fetchShares` reads only what has been downloaded, so
    /// records already in the share would count as outside it and be shared a
    /// second time. It never notes the pin as made here: that switched the
    /// wait off for the guard too (bug hunt 2026-10-09, #1).
    func mustWaitForImportAfterPin(pinnedZone: String, pinnedAt: Date?, notebookStoreID: String) -> Bool {
        forgetWhatSetupElsewhereTook(pinnedZone: pinnedZone, pinnedAt: pinnedAt)
        return waitingForImportAfterPin(notebookStoreID: notebookStoreID)
    }

    /// Whether a pin made on another device arrived here so recently that no
    /// import into the notebook has finished since. Until one has, this device
    /// may not yet hold the records that setup there moved into the share, so
    /// they'd look unshared here and be shared a second time. Clears itself
    /// once such an import is in.
    func waitingForImportAfterPin(notebookStoreID: String) -> Bool {
        guard defaults.object(forKey: Self.pinSeenAtKey) != nil else { return false }
        let seen = Date(timeIntervalSinceReferenceDate: defaults.double(forKey: Self.pinSeenAtKey))
        if let imported = ImportWatermark.lastImport(intoStoreWithIdentifier: notebookStoreID, defaults: defaults),
           imported >= seen {
            defaults.removeObject(forKey: Self.pinSeenAtKey)
            return false
        }
        return true
    }

    // MARK: - Keeping it small

    private func pruneSoon() {
        guard pruneTask == nil else { return }
        pruneTask = Task { [weak self] in
            await self?.prune()
            self?.pruneTask = nil
        }
    }

    /// Takes out what can no longer go into the share — deleted since, already
    /// in a share, or outside this school year (not while the start is still
    /// the September fallback: `ClassroomShareScope.isProvisional`) — then,
    /// while the classroom isn't shared, the oldest past the cap. With a pin
    /// nothing more goes and the length is logged. When CloudKit can't say
    /// what is shared, only the deleted and last year's go.
    func prune() async {
        guard let stack = coreDataStack else { return }
        let taken = pendingEntries
        guard !taken.isEmpty else { return }
        let container = stack.container
        let scope = self.scope()
        let sorted = await Self.sort(taken.map(\.uri), container: container, scope: scope)
        var keeping = Set(sorted.belonging.map { $0.uriRepresentation().absoluteString })
        if scope.isProvisional { keeping.formUnion(sorted.outsideScope) }
        do {
            let unshared = try await ClassroomShareAttach.unshared(sorted.belonging, container: container)
            let outside = Set(unshared)
            let shared = sorted.belonging.filter { !outside.contains($0) }
            keeping.subtract(shared.map { $0.uriRepresentation().absoluteString })
        } catch {
            // Only the deleted (and last year's) go, then.
            let detail = error.localizedDescription
            Self.logger.error("Couldn't check which waiting records are shared: \(detail, privacy: .public)")
        }
        forget(taken, except: keeping)

        let entries = pendingEntries
        guard entries.count > Self.maxPending else { return }
        if CDClassroomMembership.pinnedZoneName(in: stack.viewContext) != nil {
            Self.logger.error("Classroom attach list holds \(entries.count, privacy: .public) records; none dropped")
            return
        }
        let dropped = entries.count - Self.maxPending
        Self.logger.error("Classroom attach list full, class not shared: \(dropped, privacy: .public) oldest dropped")
        write(Array(entries.dropFirst(dropped)))
    }
}
