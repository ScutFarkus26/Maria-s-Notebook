//
//  ReplacedCopyReminders.swift
//  Cosmic Daybook
//
//  The Mac copy about to be replaced takes its reminders with it.
//  `Scripts/install_release.sh` unregisters the old copy before the new one
//  goes in, and macOS then counts the new copy as a different source of
//  notifications: the old copy's pending reminders still ring, and the new
//  copy can neither see nor cancel them. On 2026-11-13 the ParentLocker
//  reminders the copy replaced on 2026-11-11 had set up rang at 8:55 and
//  9:00 though the day was sent, and would have kept ringing for two weeks.
//
//  So before the swap the script opens the old copy once more with
//  `-CosmicDaybookClearReminders YES`: it removes its pending reminders and
//  quits, before it opens the notebook or shows a window. The new copy sets
//  up the ones still wanted when it opens (`AppBootstrapper`: the attendance
//  reminder and the monthly parent-report one).
//

import Foundation
import UserNotifications
#if os(macOS)
import Darwin
#endif

nonisolated enum ReplacedCopyReminders {

    /// The launch argument the install script passes, followed by `YES`.
    static let argument = "-CosmicDaybookClearReminders"

    /// Whether `arguments` ask for the hand-off: the argument followed by a
    /// true value (YES, true or 1, in any case). Read from argv, as
    /// `AppLaunchMode` is, so a value left in the app's defaults can't make
    /// every launch clear its reminders and quit.
    static func isRequested(arguments: [String]) -> Bool {
        guard let flag = arguments.firstIndex(of: argument), arguments.indices.contains(flag + 1) else {
            return false
        }
        return ["yes", "true", "1"].contains(arguments[flag + 1].lowercased())
    }

    #if os(macOS)
    /// When this launch is the install script's: removes this copy's pending
    /// reminders and ends the process. Otherwise returns at once. Called
    /// first thing in `CosmicDaybookApp.init`, before the stores open.
    static func handOffIfRequested(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard isRequested(arguments: arguments) else { return }
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        // The center's calls go to its daemon in order, so once this read is
        // answered the removal has been done. Waited for here (a few seconds
        // at most) because nothing else holds the process open.
        let answered = DispatchSemaphore(value: 0)
        center.getPendingNotificationRequests { _ in answered.signal() }
        _ = answered.wait(timeout: .now() + 10)
        exit(0)
    }
    #endif
}
