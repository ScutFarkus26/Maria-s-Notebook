import CoreData
import Foundation

/// Which CloudKit exports of one store are running, and when the latest began, from the
/// container's events. `ClassroomShareRelease` saves only between exports and checks that
/// an export follows each save: in the 2026-09-30 rehearsal a save made while an export ran
/// was left out of it, and no export was scheduled after, so the batch's deletes waited
/// until the app was relaunched.
nonisolated final class ClassroomShareExportActivity: @unchecked Sendable {
    private let lock = NSLock()
    private var running = Set<UUID>()
    private var latestStart: Date?
    private var observer: (any NSObjectProtocol)?

    init(storeIdentifier: String?) {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: nil
        ) { [weak self] note in
            guard let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event,
                  event.type == .export,
                  storeIdentifier == nil || event.storeIdentifier == storeIdentifier else { return }
            self?.record(id: event.identifier, start: event.startDate, finished: event.endDate != nil)
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    func record(id: UUID, start: Date, finished: Bool) {
        lock.lock(); defer { lock.unlock() }
        if finished {
            running.remove(id)
        } else {
            running.insert(id)
        }
        if latestStart.map({ start > $0 }) ?? true { latestStart = start }
    }

    var isIdle: Bool {
        lock.lock(); defer { lock.unlock() }
        return running.isEmpty
    }

    func startedAfter(_ date: Date) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return latestStart.map { $0 >= date } ?? false
    }

    /// Waits until no export runs, for at most `limit`.
    func waitUntilIdle(limit: Duration = .seconds(90)) async {
        let deadline = ContinuousClock.now.advanced(by: limit)
        while !isIdle, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    /// Whether an export starts after `date` within `limit`.
    func waitForStart(after date: Date, limit: Duration = .seconds(30)) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: limit)
        while !startedAfter(date) {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return true
    }
}
