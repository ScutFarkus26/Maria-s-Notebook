// ScheduleBookingPublisher.swift
// Keeps the classroom share's bookings in step with the guide's planned
// lessons, so the Daybook Assistant can say which children are with him and
// when, never what he's teaching. Notebook only: the Assistant reads bookings.

import CoreData
import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Writes one `CDTimetableBooking` per planned presentation from today through
/// 13 days ahead (scheduled, not yet given): its day, half or set time, place
/// in the half, and children. Every one of the guide's devices runs it, so the
/// Assistant stays current whichever device he plans on.
///
/// - **When.** A short wait after a presentation changes here (the view
///   context's edits, another context's saves) or arrives from iCloud
///   (`.presentationDataDidChange`); at launch once this launch has caught up
///   with iCloud (`ImportWatermark`, as `CalendarNotePadCopy` waits); at a new
///   day; and on return to the app. One run at a time: a change during a run
///   starts one more after it, and its own saves start none.
/// - **Never backwards.** A booking is rewritten only when the presentation's
///   `modifiedAt` is at least as new as the booking's `sourceModifiedAt` (the
///   same, when a roster edit left `modifiedAt` alone and the values differ),
///   so a device that hasn't caught up can't undo a newer plan; it removes one
///   on the same terms.
/// - **Removing.** A booking goes when its day has passed; when this device
///   knows the presentation and it was given, unscheduled or moved out of the
///   window; and when the presentation is unknown here and the booking is
///   over an hour old (a new one may still be on its way).
/// - **Doubles.** Two devices may each book one presentation. The row made
///   first (`createdAt` to the millisecond, then `id`) keeps the newest
///   values; another copy is deleted only when it's in the same CloudKit zone
///   or was never sent, and never one with the same `id`
///   (`ClassroomNames.foldCounting`'s rules). Readers take the newest per
///   presentation meanwhile (`CDTimetableBooking.newestPerPresentation`).
/// - **Saves on the view context**, so `SharedStoreOrphanGuard` shares new
///   bookings, and never alongside someone else's edit: while the view
///   context holds an unsaved change, the run waits for its next save.
///
/// Only the lead guide's devices write (`CDClassroomMembership.currentRole`),
/// only in the primary copy of the app, never on the Sample Class, whose
/// stack never reaches `AppBootstrapper`.
@MainActor
final class ScheduleBookingPublisher {

    /// What one run did.
    struct Outcome: Equatable, Sendable {
        var inserted = 0
        var updated = 0
        var removed = 0
        var folded = 0
    }

    /// Today and the 13 days after it.
    nonisolated static let windowDays = 14
    /// How old a booking for a presentation this device doesn't know must be
    /// before it goes.
    nonisolated static let unknownGrace: TimeInterval = 60 * 60
    /// The wait after a change before a run.
    nonisolated static let changeWait: Duration = .seconds(2)
    /// How long the launch waits for this launch's first import before
    /// running anyway (offline, or imports failing).
    nonisolated static let importWaitLimit: Duration = .seconds(120)
    /// A return to the app this soon after a run doesn't start another.
    nonisolated static let returnGap: TimeInterval = 60

    nonisolated static let lessonEntity = "LessonAssignment"

    let context: NSManagedObjectContext
    private let importsExpected: Bool
    private let calendar: Calendar
    private let now: () -> Date
    private let wait: Duration

    private var tokens: [any NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    private var importWait: Task<Void, Never>?
    private var launchedAt: Date?
    private var isRunning = false
    private var runAgain = false
    /// True while this publisher changes and saves bookings, so its own
    /// notifications start no run.
    private(set) var isWriting = false
    /// A run found an unsaved change in the view context; the next save there starts one.
    private var waitingForSave = false
    private(set) var isCaughtUp = false
    private var lastRunEnded: Date?

    init(
        context: NSManagedObjectContext,
        importsExpected: Bool,
        calendar: Calendar = AppCalendar.shared,
        wait: Duration = ScheduleBookingPublisher.changeWait,
        now: @escaping () -> Date = Date.init
    ) {
        self.context = context
        self.importsExpected = importsExpected
        self.calendar = calendar
        self.wait = wait
        self.now = now
    }

    // MARK: - Starting

    /// Follows the presentations, and runs once this launch has caught up
    /// with iCloud: an import into the notebook that began at or after
    /// `launchedAt` has finished (`lastImport`, its start), or right away when
    /// no imports come (`importsExpected` false). Without one within
    /// `importWaitLimit`, it runs anyway.
    func start(launchedAt: Date, lastImport: Date?, notebookStoreID: String?) {
        guard tokens.isEmpty else { return }
        self.launchedAt = launchedAt
        observe(notebookStoreID: notebookStoreID)
        if !importsExpected || CalendarNotePadCopy.caughtUp(lastImport: lastImport, launchedAt: launchedAt) {
            catchUp()
            return
        }
        importWait = Task { [weak self] in
            guard (try? await Task.sleep(for: Self.importWaitLimit)) != nil else { return }
            self?.catchUp()
        }
    }

    /// Stops following; a run under way finishes.
    func stop() {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
        tokens = []
        pending?.cancel()
        importWait?.cancel()
    }

    private func catchUp() {
        guard !isCaughtUp else { return }
        isCaughtUp = true
        importWait?.cancel()
        request()
    }

    private func observe(notebookStoreID: String?) {
        let center = NotificationCenter.default
        let viewContext = context
        let coordinatorID = context.persistentStoreCoordinator.map(ObjectIdentifier.init)
        let lessons: Set<String> = [Self.lessonEntity]
        // Edits here, saved or not, heard on the view context's own (main) queue.
        tokens.append(center.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange, object: viewContext, queue: nil
        ) { [weak self] note in
            guard Thread.isMainThread, !ManagedObjectChangeScope.touched(lessons, in: note.userInfo).isEmpty
            else { return }
            MainActor.assumeIsolated { self?.lessonsChanged() }
        })
        // Saves on the view context, for a run that waited on an unsaved edit.
        tokens.append(center.addObserver(
            forName: .NSManagedObjectContextDidSave, object: viewContext, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.viewContextSaved() }
        })
        // Saves on any other context of this stack (MCP, a background pass),
        // read on the posting thread, where only object IDs are touched.
        tokens.append(center.addObserver(
            forName: .NSManagedObjectContextDidSave, object: nil, queue: nil
        ) { [weak self] note in
            guard Self.isOtherLessonSave(note, viewContext: ObjectIdentifier(viewContext), coordinatorID: coordinatorID)
            else { return }
            Task { @MainActor in self?.lessonsChanged() }
        })
        // Presentations from iCloud.
        let key = PersistentHistoryProcessor.changedEntityNamesKey
        tokens.append(center.addObserver(
            forName: .presentationDataDidChange, object: nil, queue: .main
        ) { [weak self] note in
            guard let changed = note.userInfo?[key] as? Set<String>, changed.contains(Self.lessonEntity) else { return }
            MainActor.assumeIsolated { self?.lessonsChanged() }
        })
        // This launch's first import into the notebook.
        if let notebookStoreID {
            tokens.append(center.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification, object: nil, queue: nil
            ) { [weak self] note in
                guard let started = Self.finishedImportStart(note, storeIdentifier: notebookStoreID) else { return }
                Task { @MainActor in self?.importFinished(startedAt: started) }
            })
        }
        tokens.append(center.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.request() }
        })
        tokens.append(center.addObserver(forName: Self.becameActive, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.appBecameActive() }
        })
    }

    // MARK: - Triggers

    private func lessonsChanged() {
        guard !isWriting else { return }
        request()
    }

    private func viewContextSaved() {
        guard waitingForSave, !isWriting else { return }
        waitingForSave = false
        request()
    }

    private func importFinished(startedAt: Date) {
        guard !isCaughtUp, let launchedAt, CalendarNotePadCopy.caughtUp(lastImport: startedAt, launchedAt: launchedAt)
        else { return }
        catchUp()
    }

    private func appBecameActive() {
        if let lastRunEnded, now().timeIntervalSince(lastRunEnded) < Self.returnGap { return }
        request()
    }

    /// One run after the wait; a later request replaces the wait, and one
    /// during a run starts another after it. Before the launch has caught up,
    /// nothing runs: catching up runs once anyway.
    private func request() {
        guard isCaughtUp else { return }
        if isRunning {
            runAgain = true
            return
        }
        pending?.cancel()
        pending = Task { [weak self, wait] in
            guard (try? await Task.sleep(for: wait, tolerance: .milliseconds(500))) != nil else { return }
            await self?.runLoop()
        }
    }

    private func runLoop() async {
        guard !isRunning else {
            runAgain = true
            return
        }
        isRunning = true
        repeat {
            runAgain = false
            await publish()
        } while runAgain
        isRunning = false
        lastRunEnded = now()
    }

    // MARK: - One run

    /// One pass: writes this device's bookings and saves, then folds doubles.
    /// Nil when it didn't run: not the lead guide's device, a second copy of
    /// the app, an unsaved edit in the view context (it waits for the next
    /// save), or a save that failed (its own changes are rolled back).
    @discardableResult
    func publish() async -> Outcome? {
        guard !CoreDataStack.isSecondaryProcess,
              CDClassroomMembership.currentRole(in: context) == .leadGuide else { return nil }
        guard !context.hasChanges else {
            waitingForSave = true
            return nil
        }
        isWriting = true
        var outcome = Self.write(in: context, now: now(), calendar: calendar)
        let saved = save()
        isWriting = false
        guard saved else { return nil }
        outcome.folded = await foldDoubles()
        return outcome
    }

    private func save() -> Bool {
        guard context.hasChanges else { return true }
        if context.safeSave() { return true }
        context.rollback()
        return false
    }

    /// Folds bookings two devices made for one presentation, after asking
    /// CloudKit where they live (off the main thread, one lookup at a time, as
    /// the name list asks). Nothing when an edit started in the view context
    /// meanwhile; the next run folds.
    private func foldDoubles() async -> Int {
        let asked = Self.doubles(in: context).flatMap { $0.map(\.objectID) }
        guard !asked.isEmpty else { return 0 }
        await ClassroomNames.gate.enter()
        let zones = await ClassroomNames.lookUpZones(of: asked, in: context)
        ClassroomNames.gate.leave()
        guard zones.answered, !context.hasChanges else { return 0 }
        isWriting = true
        defer { isWriting = false }
        let folded = Self.doubles(in: context).reduce(0) { $0 + Self.fold($1, zones: zones, in: context) }
        // A fold that deleted nothing may still have given the kept copy newer values.
        guard save() else { return 0 }
        return folded
    }

    // MARK: - Notifications, read off the main thread

    private static var becameActive: Notification.Name {
        #if canImport(UIKit)
        UIApplication.didBecomeActiveNotification
        #else
        NSApplication.didBecomeActiveNotification
        #endif
    }

    /// Whether a save on another context of this stack touched a presentation.
    nonisolated static func isOtherLessonSave(
        _ note: Notification, viewContext: ObjectIdentifier, coordinatorID: ObjectIdentifier?
    ) -> Bool {
        guard let saver = note.object as? NSManagedObjectContext, ObjectIdentifier(saver) != viewContext else {
            return false
        }
        if let coordinatorID {
            guard let coordinator = saver.persistentStoreCoordinator,
                  ObjectIdentifier(coordinator) == coordinatorID else { return false }
        }
        return !ManagedObjectChangeScope.touched([lessonEntity], in: note.userInfo).isEmpty
    }

    /// When an import into the notebook that finished and worked began.
    nonisolated static func finishedImportStart(_ note: Notification, storeIdentifier: String) -> Date? {
        guard RemoteImportReloader.isFinishedImport(note, storeIdentifier: storeIdentifier),
              let event = note.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                as? NSPersistentCloudKitContainer.Event
        else { return nil }
        return event.startDate
    }

    /// When this process started, from the kernel: "this launch" for the
    /// catch-up, since the launch's first import begins before the
    /// publisher starts.
    nonisolated static func processStartDate() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        guard start.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
