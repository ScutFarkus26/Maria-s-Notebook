import Foundation
import CoreData
import OSLog
import UIKit

/// Puts the Assistant's new marks into the classroom share, one pass at a
/// time, and keeps what didn't go in to try again.
///
/// Every save used to start its own attach. A morning's first taps started a
/// dozen at once, each holding a thread while `share(_:to:)` waited on its
/// export, and share saves running together can leave Core Data retrying a
/// stale change tag. A mark that didn't go in (no pin yet, CloudKit busy) was
/// only logged, and never reached the guide. Now passes run one after
/// another, and what's left waits in a short persisted list for the next
/// save, when the rest after a failed pass ends, when the app comes back to
/// the foreground, or at launch. Only her own new records are ever in it, so
/// this is not the sweep the notebook gave up.
@MainActor
final class AssistantShareAttacher {
    static let shared: AssistantShareAttacher = {
        let attacher = AssistantShareAttacher()
        attacher.retryOnReturnToForeground()
        return attacher
    }()

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
    /// After a pass leaves marks behind, the backlog rests (`rest(afterFailures:)`)
    /// before it's tried again, so a CloudKit that keeps refusing doesn't turn
    /// every tap into a retry of every waiting mark. When the rest ends it's
    /// tried on its own, without waiting for a tap.
    private var backlogWaitsUntil = Date.distantPast
    private var failuresInARow = 0
    private var retryTask: Task<Void, Never>?
    /// What the last pass was given, for retries nobody asked for.
    private weak var lastContainer: NSPersistentCloudKitContainer?
    private weak var lastContext: NSManagedObjectContext?
    private var foregroundObserver: (any NSObjectProtocol)?
    /// A pass that goes in ends the rest early, once: if the waiting marks are
    /// refused even then, it's something about them, not CloudKit, and they
    /// wait out the full rest rather than riding along with every tap.
    private var triedEarly = false
    private var earlyTryFailed = false
    private let defaults: UserDefaults
    private let now: @MainActor () -> Date
    private let sleep: Sleep

    /// One try at putting records into the share; returns those to try again.
    typealias Attempt = @MainActor (
        _ ids: [NSManagedObjectID],
        _ container: NSPersistentCloudKitContainer,
        _ context: NSManagedObjectContext
    ) async -> [NSManagedObjectID]
    private let attempt: Attempt
    /// Waits out a rest before the retry; throws to cancel it.
    typealias Sleep = @MainActor (_ seconds: TimeInterval) async throws -> Void

    /// Tests pass `now`, `sleep` and `attempt`: the real attempt needs a
    /// classroom share.
    init(
        defaults: UserDefaults = .standard,
        now: @escaping @MainActor () -> Date = Date.init,
        sleep: @escaping Sleep = { try await Task.sleep(for: .seconds($0)) },
        attempt: @escaping Attempt = { ids, container, context in
            await CDAttendanceStore.attachNewRecordsToClassroomShare(ids, container: container, pinContext: context)
        }
    ) {
        self.defaults = defaults
        self.now = now
        self.sleep = sleep
        self.attempt = attempt
    }

    /// One minute after the first failed pass in a row, doubling each time
    /// after, and never more than ten.
    static func rest(afterFailures failures: Int) -> TimeInterval {
        min(60 * pow(2, Double(max(failures, 1) - 1)), 10 * 60)
    }

    /// Whether a pass is running now.
    var isRunning: Bool { pass != nil }

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

    /// Tries what was just saved, and the backlog unless it's resting after a
    /// failed pass: at launch, and after each save.
    func flush(container: NSPersistentCloudKitContainer, context: NSManagedObjectContext) {
        lastContainer = container
        lastContext = context
        guard pass == nil else {
            runAgain = true
            return
        }
        pass = Task { [weak self] in
            await self?.run(container: container, context: context)
            self?.pass = nil
        }
    }

    /// Tries every waiting mark now, rest or no rest, with what the last pass
    /// was given. Nothing happens before the first pass, or with nothing waiting.
    func retryWaiting() {
        guard let lastContainer, let lastContext, !pending.isEmpty else { return }
        backlogWaitsUntil = .distantPast
        flush(container: lastContainer, context: lastContext)
    }

    /// Coming back to the app is a good moment: the phone may have found
    /// Wi-Fi, and she's about to look at whether her marks went.
    private func retryOnReturnToForeground() {
        foregroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.retryWaiting() }
        }
    }

    private func scheduleRetry(after seconds: TimeInterval) {
        retryTask?.cancel()
        retryTask = Task { [weak self, sleep] in
            do { try await sleep(seconds) } catch { return }
            guard !Task.isCancelled else { return }
            self?.retryWaiting()
        }
    }

    /// Returns once no pass is running: Siri keeps its launch alive this long.
    func waitUntilIdle() async {
        while let pass { await pass.value }
    }

    private func run(container: NSPersistentCloudKitContainer, context: NSManagedObjectContext) async {
        repeat {
            runAgain = false
            let backlogDue = now() >= backlogWaitsUntil
            if backlogDue, !triedEarly { earlyTryFailed = false }
            let wasEarly = triedEarly
            triedEarly = false
            let justSaved = fresh
            fresh = []
            let taken = pending.filter { backlogDue || justSaved.contains($0.absoluteString) }
            let ids = resolve(taken, in: context)
            guard !ids.isEmpty else {
                forget(taken)
                continue
            }
            let left = await attempt(ids, container, context)
            // Marks saved during the pass stay; of these, only what failed.
            forget(taken)
            remember(left.map { $0.uriRepresentation() })
            if left.isEmpty {
                failuresInARow = 0
                if backlogDue {
                    backlogWaitsUntil = .distantPast
                } else if !pending.isEmpty, !earlyTryFailed {
                    // CloudKit took every mark it was given, so it's working:
                    // go round now for the marks it held back.
                    backlogWaitsUntil = .distantPast
                    triedEarly = true
                    runAgain = true
                }
            } else {
                if wasEarly { earlyTryFailed = true }
                failuresInARow += 1
                let rest = Self.rest(afterFailures: failuresInARow)
                backlogWaitsUntil = now().addingTimeInterval(rest)
                scheduleRetry(after: rest)
                Self.logger.notice(
                    "\(left.count, privacy: .public) mark(s) wait \(Int(rest), privacy: .public) s for the next try"
                )
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

    /// The waiting list, oldest first.
    var pending: [URL] {
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
