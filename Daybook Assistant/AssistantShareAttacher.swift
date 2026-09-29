import Foundation
import CoreData
import OSLog

/// Puts the Assistant's new marks into the classroom share, one pass at a
/// time, and keeps what didn't go in to try again.
///
/// Every save used to start its own attach. A morning's first taps started a
/// dozen at once, each holding a thread while `share(_:to:)` waited on its
/// export, and share saves running together can leave Core Data retrying a
/// stale change tag. A mark that didn't go in (no pin yet, CloudKit busy) was
/// only logged, and never reached the guide. Now passes run one after
/// another, and what's left waits in a short persisted list for the next
/// save or launch. Only her own new records are ever in it, so this is not
/// the sweep the notebook gave up.
@MainActor
final class AssistantShareAttacher {
    static let shared = AssistantShareAttacher()

    private static let logger = Logger.app(category: "shareAttach")
    /// The list's length at most, oldest dropped first: a class's marks for
    /// three weeks, far more than a working phone ever holds back.
    private static let cap = 500
    /// Object URIs name one store, so the list is per CloudKit environment.
    private static var key: String { CloudKitEnvironment.scoped("Assistant.pendingShareAttach") }

    private var pass: Task<Void, Never>?
    private var runAgain = false
    /// Saved since the last pass began: always tried.
    private var fresh: Set<String> = []
    /// After a pass leaves marks behind, the backlog waits this long before
    /// it's tried again, so a CloudKit that keeps refusing doesn't turn every
    /// tap into a retry of every waiting mark.
    private var backlogWaitsUntil = Date.distantPast
    private static let backlogPause: TimeInterval = 10 * 60
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Remembers `ids` (just saved) and starts a pass, or asks the running
    /// one to go round again.
    func attach(
        _ ids: [NSManagedObjectID],
        container: NSPersistentCloudKitContainer,
        context: NSManagedObjectContext
    ) {
        let uris = ids.map { $0.uriRepresentation() }
        remember(uris)
        fresh.formUnion(uris.map(\.absoluteString))
        flush(container: container, context: context)
    }

    /// Tries what was just saved, and the backlog unless it's paused after a
    /// failed pass: at launch, and after each save.
    func flush(container: NSPersistentCloudKitContainer, context: NSManagedObjectContext) {
        guard pass == nil else {
            runAgain = true
            return
        }
        pass = Task { [weak self] in
            await self?.run(container: container, context: context)
            self?.pass = nil
        }
    }

    /// Returns once no pass is running: Siri keeps its launch alive this long.
    func waitUntilIdle() async {
        while let pass { await pass.value }
    }

    private func run(container: NSPersistentCloudKitContainer, context: NSManagedObjectContext) async {
        repeat {
            runAgain = false
            let backlogDue = Date() >= backlogWaitsUntil
            let justSaved = fresh
            fresh = []
            let taken = pending.filter { backlogDue || justSaved.contains($0.absoluteString) }
            let ids = resolve(taken, in: context)
            guard !ids.isEmpty else {
                forget(taken)
                continue
            }
            let left = await CDAttendanceStore.attachNewRecordsToClassroomShare(
                ids, container: container, pinContext: context
            )
            // Marks saved during the pass stay; of these, only what failed.
            forget(taken)
            remember(left.map { $0.uriRepresentation() })
            if left.isEmpty {
                if backlogDue { backlogWaitsUntil = .distantPast }
            } else {
                backlogWaitsUntil = Date().addingTimeInterval(Self.backlogPause)
                Self.logger.notice("\(left.count, privacy: .public) mark(s) wait for the next try")
            }
        } while runAgain
    }

    /// The waiting records that still exist.
    private func resolve(_ uris: [URL], in context: NSManagedObjectContext) -> [NSManagedObjectID] {
        guard let coordinator = context.persistentStoreCoordinator else { return [] }
        return uris.compactMap { uri in
            guard let id = coordinator.managedObjectID(forURIRepresentation: uri),
                  (try? context.existingObject(with: id)) != nil else { return nil }
            return id
        }
    }

    private var pending: [URL] {
        (defaults.stringArray(forKey: Self.key) ?? []).compactMap(URL.init(string:))
    }

    private func remember(_ uris: [URL]) {
        guard !uris.isEmpty else { return }
        var list = defaults.stringArray(forKey: Self.key) ?? []
        for uri in uris.map(\.absoluteString) where !list.contains(uri) { list.append(uri) }
        defaults.set(Array(list.suffix(Self.cap)), forKey: Self.key)
    }

    private func forget(_ uris: [URL]) {
        let gone = Set(uris.map(\.absoluteString))
        let list = (defaults.stringArray(forKey: Self.key) ?? []).filter { !gone.contains($0) }
        defaults.set(list, forKey: Self.key)
    }
}
