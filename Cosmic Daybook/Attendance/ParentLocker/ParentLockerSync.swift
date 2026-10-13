import Foundation
import CoreData
import Observation
import OSLog

/// Sends the class's attendance to ParentLocker and keeps it there (plan
/// "ParentLocker attendance", Sending at Close Arrival, then live):
/// - **Nothing before "after".** Nothing goes until arrival has closed or the
///   day's ParentLocker send is recorded, so the office never sees a
///   half-taken class. Close Arrival & Send made here, or a whole-class send
///   started here, keeps the day "after" on this device until its Undo,
///   whatever the automatic absences say since. A change made before "after"
///   isn't dropped: this device's own goes as its own once the day is (a
///   minute after another device closed arrival, so that device's send has
///   gone first), and is kept across launches; one synced in goes as such.
/// - **Close Arrival & Send** (`closeArrivalSend`) sends the whole class once
///   Close Arrival's Undo has gone (`undoEndsAt`), never earlier, a sign-in
///   meanwhile included; Undo (`cancelCloseArrivalSend`) stops it. **Send
///   Now** and MCP (`sendNow`, `send(day:preview:)`) send a whole day at
///   once, never one that hasn't come yet; another day's leaves today's line
///   alone. A whole-class send records the day's send if none is yet.
/// - **Then each change goes live, one child at a time:** one made on this
///   device after 4 s of quiet, one synced in from another after 60 s (the
///   backstop for a phone that's offline or not signed in), each compared
///   with ParentLocker and saved only where it differs.
/// - **An imported change goes only over what this device last saw** in
///   ParentLocker for that child (`lastSeen`, read as it arrives when there's
///   nothing yet); anything else there was saved since by another device,
///   maybe with a newer mark, and is left to it. The guide's backstops too.
/// - **The guide's backstop:** arrival closed with no ParentLocker send
///   recorded within 60 s, and one of the guide's signed-in devices sends
///   the whole class and records it. Likewise a minute after the day's due
///   time, when everyone is marked and nothing was sent (a Close Arrival
///   with nobody left to mark leaves no automatic absence to see).
/// - **On launch and on the way back** the changes this device still owes go
///   once the first CloudKit import is in, so they're compared with fresh
///   marks, or after 20 s without one; a retry due meanwhile waits with
///   them. On the Mac only a return after a minute away counts, not every
///   switch between apps. At midnight what's owed goes, and the line moves on.
/// - Failures retry after 30 s, 2 min and 5 min, then wait; a whole-class
///   retry, like the backstop, goes only over what this device last saw in
///   ParentLocker, and another day's retry never takes today's. Nothing polls:
///   one task sleeps until the next thing is due, on an injected clock. A
///   saved password ParentLocker refused isn't tried again by itself until a
///   new one is saved.
///
/// Live updates run only while ParentLocker is the method, this device is
/// signed in, the day is a school day and today, and the day is past
/// "after". A Debug build or a test run reads and plans but never saves
/// (`ParentLockerSavePolicy`). Compiled into the notebook and the Daybook
/// Assistant: start one per app on the classroom's context (`start`), never
/// on the Sample Class.
@MainActor
@Observable
final class ParentLockerSync {

    // MARK: - Timing (plan: 4 s local, 60 s imported and backstop, 30 s / 2 min / 5 min retries)

    nonisolated static let localQuiet: TimeInterval = 4
    nonisolated static let importedWait: TimeInterval = 60
    nonisolated static let backstopWait: TimeInterval = 60
    nonisolated static let retryWaits: [TimeInterval] = [30, 120, 300]
    /// How long the catch-up waits for a CloudKit import that may never come.
    nonisolated static let importWaitLimit: TimeInterval = 20
    /// How long the Mac app must have been in the background for its return
    /// to count as one.
    nonisolated static let returnAbsence: TimeInterval = 60
    /// How long Close Arrival's Undo stays offered when the screen doesn't say.
    nonisolated static let closeArrivalUndoWindow: TimeInterval = 6

    /// Signs in through the site's own form and returns the cookies it set.
    typealias SignIn = @MainActor (ParentLockerKeychain.Credential, _ site: String) async throws -> [ParentLockerCookie]
    /// Makes the transport for `site` with `cookies`; `cookiesChanged` hears each change.
    typealias MakeTransport = @MainActor (
        _ site: String, _ cookies: [ParentLockerCookie],
        _ cookiesChanged: @escaping @Sendable ([ParentLockerCookie]) -> Void
    ) -> any ParentLockerTransport

    /// Everything the sync is handed rather than reaching for.
    struct Dependencies {
        var store: any ParentLockerStore
        var secrets: any ParentLockerSecrets = ParentLockerKeychainSecrets()
        var makeTransport: MakeTransport = { site, cookies, changed in
            ParentLockerHTTP(site: site, cookies: cookies, cookiesChanged: changed)
        }
        var signIn: SignIn = { credential, site in
            try await ParentLockerSignIn(site: site).run(credential, showsPagesWhenAsked: false)
        }
        var clock: any ParentLockerClock = ParentLockerSystemClock()
        var policy: ParentLockerSavePolicy = .current
        var unsent: any ParentLockerUnsentStore = ParentLockerSync.defaultUnsentStore()
        /// The saved password ParentLocker refused, remembered across launches
        /// in a build that saves.
        var refusals: any ParentLockerRefusalStore = ParentLockerSavePolicy.current.allowsSaving
            ? ParentLockerDefaultsRefusalStore() : ParentLockerMemoryRefusalStore()
        var background: any ParentLockerBackgroundWork = ParentLockerSystemBackgroundWork()
        var isInForeground: @MainActor () -> Bool = { ParentLockerAppState.isInForeground() }
        /// Whether CloudKit imports will come: false for a stack without
        /// CloudKit, where the catch-up needn't wait for one.
        var importsExpected = true
        /// Whether becoming active counts as a return only after
        /// `returnAbsence` away: on the Mac, which becomes active at every
        /// switch between apps.
        #if os(macOS)
        var returnNeedsAbsence = true
        #else
        var returnNeedsAbsence = false
        #endif
        var calendar: Calendar = AppCalendar.shared
    }

    // MARK: - What the screens read (only the sync sets them)

    var status = ParentLockerStatus()
    /// A ParentLocker password is saved for the site (on this device, or synced to it).
    var isSignedIn = false
    /// The last whole-day plan or preview.
    var lastReport: ParentLockerReport?
    /// When Close Arrival's Undo ends for the Close Arrival & Send made here
    /// today: the send goes no earlier, and a screen offers its Undo until
    /// then. Nil when there is none, or once Undo was used.
    private(set) var undoEndsAt: Date?
    /// ParentLocker refused the saved password, and no new one has been
    /// saved since: the app doesn't sign in with it by itself (Sign In again).
    var savedPasswordRefused = false
    /// ParentLocker wanted something only a person can do when the app
    /// signed in by itself (new terms, a reset), and nobody has signed in
    /// since, through the sheet or with a new password saved on another of
    /// the person's devices: the app doesn't sign in by itself meanwhile.
    var signInNeedsYou = false

    /// The screens' question: not signed in, signed in with a password
    /// ParentLocker refused, or ParentLocker wants a person to sign in (new
    /// terms, a reset). Either way Close Arrival & Send and Send Now open the
    /// sign-in sheet, and the menus offer Sign In.
    var needsSignIn: Bool { !isSignedIn || savedPasswordRefused || signInNeedsYou }
    /// A whole-class send is waiting for a sign-in, today only, so a screen
    /// can prompt for one (bug hunt 2026-10-13 afternoon, L2/L6): Close
    /// Arrival & Send or Send Now made while `needsSignIn`, or one refused
    /// for want of a sign-in. A sign-in, the sheet closing
    /// (`signInDismissed`), Undo and a new day clear it.
    var awaitsSignIn = false

    /// The sync the app started, for the screens, intents and MCP that
    /// aren't handed one.
    static private(set) weak var current: ParentLockerSync?

    // MARK: - What's owed and when

    let dependencies: Dependencies
    var store: any ParentLockerStore { dependencies.store }
    var clock: any ParentLockerClock { dependencies.clock }

    /// This device's changes not in ParentLocker yet, by when each was made.
    @ObservationIgnored var localChanges: [UUID: Date] = [:]
    @ObservationIgnored var localDue: Date?
    /// Owed from before launch or the trip away: held until the first import.
    @ObservationIgnored var catchUpChildren: Set<UUID> = []
    @ObservationIgnored var importedChildren: Set<UUID> = []
    /// What this device had seen of each imported child in ParentLocker when
    /// the change was noted (none: never seen).
    @ObservationIgnored var importedBaseline: [UUID: ParentLockerSeen] = [:]
    @ObservationIgnored var importedDue: Date?
    /// What ParentLocker held for each child when this device last looked:
    /// today's rosters and saves.
    @ObservationIgnored var lastSeen: [UUID: ParentLockerSeen] = [:]
    /// Each child synced in with no row seen to measure the change by: their
    /// mark here from before it (nil: unmarked), when this device knew it.
    @ObservationIgnored var importedBefore: [UUID: ParentLockerPlanner.DayMark?] = [:]
    /// Today's marks as this device last read them, for `importedBefore`;
    /// nil when it hasn't read them today.
    @ObservationIgnored var knownMarks: [UUID: ParentLockerPlanner.DayMark]?
    /// The day `knownMarks` were read for.
    @ObservationIgnored var knownMarksDay: Date?
    /// Changes synced in before "after": nothing goes for them yet. Once the
    /// day is "after" here they go as changes synced in do
    /// (`releaseEarlyChanges`), or with this device's own whole-class send.
    @ObservationIgnored var earlyChanges: Set<UUID> = []
    /// This device's own changes made before "after", kept with what's owed
    /// across launches. Once the day is "after" here they go as this
    /// device's own changes, over whatever ParentLocker holds then
    /// (`earlyLocalDue`), or with its own whole-class send.
    @ObservationIgnored var earlyLocal: Set<UUID> = []
    /// When `earlyLocal` goes, once the day is "after": a minute after
    /// another device's Close Arrival was seen here, so that device's send,
    /// made from a view without these marks, has landed first; seconds
    /// after, once the day's send is recorded.
    @ObservationIgnored var earlyLocalDue: Date?
    @ObservationIgnored var wholeClass: ParentLockerWholeClass?
    /// Today's retry. Another day's (Send Now, MCP) has its own slot, so it
    /// never takes today's place.
    @ObservationIgnored var retry: (job: ParentLockerJob, due: Date)?
    @ObservationIgnored var otherDayRetry: (job: ParentLockerJob, due: Date)?
    @ObservationIgnored var awaitingImport = false
    /// When the catch-up stops waiting for the import.
    @ObservationIgnored var importWaitEnds: Date?
    /// When the Mac app last went to the background.
    @ObservationIgnored var resignedAt: Date?
    /// The day the owed changes are for: today when they were made.
    @ObservationIgnored var owedDay: Date?
    /// Close Arrival & Send was made here today, or a whole-class send
    /// started: today is "after" on this device whatever the automatic
    /// absences say now. Only that Close Arrival's Undo clears it.
    @ObservationIgnored var arrivalClosedHere = false
    /// The day the guide's backstop last went or was scheduled (cleared when
    /// one is refused, so the next can come).
    @ObservationIgnored var backstopDay: Date?
    /// The sign-in sheet closed without a sign-in: the send owed since
    /// doesn't ask for one again by itself each time a change takes it and
    /// it fails again. Close Arrival & Send, Send Now, Undo, a sign-in and a
    /// new day clear it.
    @ObservationIgnored var signInDeclined = false
    /// When the saved password was saved, as ParentLocker wanted a person at
    /// its sign-in (`signInNeedsYou`): a newer one clears that.
    @ObservationIgnored var needsYouPassword: Date?
    /// When the guide's device checks, after the day's due time, whether the
    /// class was taken but never sent.
    @ObservationIgnored var deadlineDue: Date?

    @ObservationIgnored var wakeTask: Task<Void, Never>?
    /// Reading the class lists for changes synced in with nothing seen to
    /// measure them by (`loadBaseline`).
    @ObservationIgnored var baselineTask: Task<Void, Never>?
    /// The children `baselineTask` is reading for.
    @ObservationIgnored var baselineWaiting: Set<UUID> = []
    /// The children the class lists were read for today: each at most once a
    /// day, since one ParentLocker doesn't hold (not matched, or in a class it
    /// leaves alone) never gets a `lastSeen` to stop the next read.
    @ObservationIgnored var baselineRead: Set<UUID> = []
    /// The class lists are being read for `baselineTask`: a run waits for it,
    /// as the read waits for a run, so the two never sign in at once.
    @ObservationIgnored var readingBaseline = false
    @ObservationIgnored var activeRun: Task<ParentLockerRunOutcome, Never>?
    @ObservationIgnored private var watcher: ParentLockerWatcher?
    @ObservationIgnored var holdsBackground = false
    /// Stopped: nothing more is scheduled, and no background window is held.
    @ObservationIgnored var isStopped = false

    static let logger = Logger.attendance

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    /// The sync on a Core Data context, as the apps make it. `save` saves a
    /// send record or a match (the Assistant's files a new record into the share).
    convenience init(
        context: NSManagedObjectContext,
        save: @escaping ParentLockerCoreDataStore.Save = { context, _ in context.safeSave() },
        importsExpected: Bool = true
    ) {
        var dependencies = Dependencies(store: ParentLockerCoreDataStore(context: context, save: save))
        dependencies.importsExpected = importsExpected
        self.init(dependencies: dependencies)
    }

    /// A sync let go without `stop()`: its iPhone background window goes
    /// with `dependencies.background`, whose own deinit ends it.
    deinit {
        wakeTask?.cancel()
        baselineTask?.cancel()
    }

    // MARK: - Starting and stopping

    /// Starts following the class: reads the sign-in, picks up what this
    /// device still owes (sent once the first import is in), and watches
    /// `context`'s saves, CloudKit's imports, a new day and the app coming
    /// and going. Pass nil to watch nothing (tests drive the sync by hand).
    func start(watching context: NSManagedObjectContext?) {
        isStopped = false
        Self.current = self
        refreshSignIn()
        loadOwed()
        // Today's marks as they stand, for the changes synced in from here on.
        if isSignedIn { rememberMarks(store.day(today, withChildren: true)) }
        if let context { watcher = ParentLockerWatcher(context: context, sync: self) }
        waitForImport()
        refreshStatus()
    }

    /// Stops watching and drops anything scheduled (what's owed stays saved).
    /// A stopped sync schedules nothing more and lets the iPhone's background
    /// window go, so the window can't outlive it.
    func stop() {
        isStopped = true
        watcher = nil
        wakeTask?.cancel()
        wakeTask = nil
        baselineTask?.cancel()
        if Self.current === self { Self.current = nil }
        updateBackgroundHold(force: false)
    }

    // MARK: - Close Arrival, Send Now, MCP

    /// Close Arrival & Send: the whole class goes once `undoWindow` has passed
    /// without `cancelCloseArrivalSend`. Changes made meanwhile wait for it,
    /// and a child marked Late meanwhile doesn't stop it: arrival stays
    /// closed here until that Undo. Today only; other days go through Send
    /// Now. On a device that needs a sign-in, the send waits for one
    /// (`awaitsSignIn`), and goes no earlier than the Undo's end (the guide's
    /// backstop covers it if nobody signs in).
    func closeArrivalSend(on day: Date, after undoWindow: TimeInterval = closeArrivalUndoWindow) {
        guard isToday(day) else { return }
        rollOwedDay(to: day)
        let undoEnds = clock.now.addingTimeInterval(undoWindow)
        undoEndsAt = undoEnds
        // A backstop this takes the place of didn't go: the day stays open to the next.
        if wholeClass?.reason == .backstop { backstopDay = nil }
        wholeClass = ParentLockerWholeClass(reason: .closeArrival, due: needsSignIn ? nil : undoEnds)
        awaitsSignIn = needsSignIn
        signInDeclined = false
        arrivalClosedHere = true
        saveOwed()
        reschedule()
    }

    /// Siri's Close Arrival on a device that's signed in: Close Arrival &
    /// Send with no Undo window to wait out, so the class goes now. It goes
    /// as a Close Arrival & Send, never a Send Now, so a failed send's retry
    /// (and the send owed once the retries run out) stays one, and Siri's
    /// "Undo that" (`cancelCloseArrivalSend`) stops it (review of the
    /// afternoon fixes, H2). Returns how it went. On a device that needs a
    /// sign-in it waits for one, as Close Arrival & Send does.
    @discardableResult
    func closeArrivalSendNow(on day: Date) async -> ParentLockerStatus {
        guard isToday(day) else { return status }
        closeArrivalSend(on: day, after: 0)
        guard wholeClass?.reason == .closeArrival, wholeClass?.due != nil else {
            return ParentLockerStatus(state: .waitingForSignIn)
        }
        wholeClass = nil
        return await run(wholeClassJob(.closeArrival)).status
    }

    /// Close Arrival's Undo: the pending send doesn't go, and arrival is open
    /// again here. ParentLocker can't take a mark back, so this is the last
    /// moment it can be stopped. That covers a send that failed and waits to
    /// try again (its retry, or the send owed once the retries ran out),
    /// which would otherwise send the reopened class (bug hunt 2026-10-13
    /// afternoon, H2).
    func cancelCloseArrivalSend() {
        let waiting = wholeClass?.reason == .closeArrival
        let retrying = retry.map { $0.job.reason == .closeArrival && isToday($0.job.day) } ?? false
        guard waiting || retrying else { return }
        if waiting { wholeClass = nil }
        if retrying { retry = nil }
        awaitsSignIn = false
        signInDeclined = false
        arrivalReopenedHere()
        reschedule()
    }

    /// Arrival is open again here (Close Arrival's Undo, or a Close Arrival &
    /// Send refused because the day was reset since): the lasting "arrival
    /// closed here" mark and Undo's end go.
    func arrivalReopenedHere() {
        arrivalClosedHere = false
        undoEndsAt = nil
        // Its own changes from before wait for "after" again.
        earlyLocalDue = nil
        saveOwed()
    }

    /// Send Now: the whole class for `day`, now. Records the day's send,
    /// unless it's recorded already or someone on the roll is still unmarked.
    /// Returns how this send went (for another day, only here: the line is
    /// today's). On a device that needs a sign-in, today's waits for one and
    /// goes once it's made, with no second tap; another day's just says to
    /// sign in (bug hunt 2026-10-13 afternoon, L6).
    @discardableResult
    func sendNow(day: Date) async -> ParentLockerStatus {
        // Asked for now: it may ask for a sign-in again if it needs one.
        if isToday(day) { signInDeclined = false }
        guard needsSignIn, !isAhead(day) else { return await run(askedJob(day, reason: .sendNow)).status }
        if isToday(day) { sendAfterSignIn() }
        return ParentLockerStatus(state: .waitingForSignIn)
    }

    /// A whole day for MCP and the Debug preview: `preview` reads and plans
    /// only, whatever the method; otherwise it sends and records the send, as
    /// Send Now does. Never a day that hasn't come yet. The failure says why
    /// in plain words.
    func send(day: Date, preview: Bool) async -> Result<ParentLockerReport, ParentLockerSendFailure> {
        await run(askedJob(day, reason: .request, preview: preview)).result
    }

    /// A whole day someone asked for. Today's covers the changes noted
    /// before it, which it settles once it reaches ParentLocker.
    private func askedJob(_ day: Date, reason: ParentLockerJob.Reason, preview: Bool = false) -> ParentLockerJob {
        var job = ParentLockerJob(day: day, children: nil, reason: reason, preview: preview)
        if isToday(day) { job.settles = importedChildren.union(earlyChanges).union(earlyLocal) }
        return job
    }
}
