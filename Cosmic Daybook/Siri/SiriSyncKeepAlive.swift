//
//  SiriSyncKeepAlive.swift
//  Cosmic Daybook
//
//  Siri runs an attendance intent without opening the app, and iOS suspends
//  the app soon after the intent answers. A mark saved just before that would
//  sit on the phone until the next launch; these keep the process awake long
//  enough for it to reach iCloud (and, in Daybook Assistant, the classroom
//  share), and let Siri answer straight away.
//
//  Shared with Daybook Assistant, which compiles this file by path. It stays
//  on the classic `eventChangedNotification`: the Assistant supports iOS 18.
//

import CoreData
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum SiriSyncKeepAlive {
    /// Runs `work` under a background-task assertion on iOS, so a suspended
    /// app finishes it; elsewhere it simply runs.
    static func run(_ work: @escaping @MainActor () async -> Void) {
        #if canImport(UIKit)
        let token = BackgroundTaskToken()
        token.id = UIApplication.shared.beginBackgroundTask(withName: "Siri attendance sync") {
            token.end()
        }
        Task {
            await work()
            token.end()
        }
        #else
        Task { await work() }
        #endif
    }

    #if canImport(UIKit)
    private final class BackgroundTaskToken {
        var id: UIBackgroundTaskIdentifier = .invalid

        func end() {
            guard id != .invalid else { return }
            UIApplication.shared.endBackgroundTask(id)
            id = .invalid
        }
    }
    #endif
}

/// Waits for the next CloudKit export to finish, or a time limit. Created
/// before the save it follows, so an export that finishes quickly is caught.
@MainActor
final class SiriExportWatch {
    private var observer: (any NSObjectProtocol)?
    private var finished = false
    private var continuation: CheckedContinuation<Void, Never>?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
            let exportEnded = event?.type == .export && event?.endDate != nil
            guard exportEnded else { return }
            MainActor.assumeIsolated { self?.stop() }
        }
    }

    func wait(upTo limit: Duration) async {
        guard !finished else { return }
        let timer = Task { [weak self] in
            try? await Task.sleep(for: limit)
            self?.stop()
        }
        await withCheckedContinuation { continuation = $0 }
        timer.cancel()
    }

    /// Ends the wait (or stops watching before one starts).
    func stop() {
        finished = true
        if let observer {
            NotificationCenter.default.removeObserver(observer)
            self.observer = nil
        }
        continuation?.resume()
        continuation = nil
    }
}
