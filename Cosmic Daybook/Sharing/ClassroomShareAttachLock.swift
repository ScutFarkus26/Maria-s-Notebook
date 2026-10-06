import Foundation

/// Held by everything on this device that puts records into the classroom
/// share: Set Up Classroom Sharing (and "Add them to the share", which runs it
/// again), the Mac's one-time "Add this year's attendance to the share", and
/// `SharedStoreOrphanGuard`'s passes. Two at once could each find the same
/// record unshared and ask CloudKit to share it twice, which fails; on
/// 2026-09-27 sharing an already-shared record stopped the export for the
/// session. Waiters go in the order they asked.
@MainActor
final class ClassroomShareAttachLock {
    static let shared = ClassroomShareAttachLock()

    private(set) var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard isHeld else {
            isHeld = true
            return
        }
        // `release` hands the lock over still held.
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        guard !waiters.isEmpty else {
            isHeld = false
            return
        }
        waiters.removeFirst().resume()
    }

    /// Runs `work` holding the lock.
    func run<T>(_ work: () async throws -> T) async rethrows -> T {
        await acquire()
        defer { release() }
        return try await work()
    }
}
