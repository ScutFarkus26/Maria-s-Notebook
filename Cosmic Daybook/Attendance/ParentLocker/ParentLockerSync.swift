import Foundation
import CoreData
import Observation
import OSLog

/// Sends the class's attendance to ParentLocker and keeps it there (plan
/// "ParentLocker attendance", Sending at Close Arrival, then live):
/// - **Nothing before "after".** Nothing goes until arrival has closed or the
///   day's ParentLocker send is recorded, so the office never sees a
///   half-taken class.
/// - **Close Arrival & Send** (`closeArrivalSend`) sends the whole class once
///   Close Arrival's Undo has gone; Undo (`cancelCloseArrivalSend`) stops it.
///   **Send Now** and MCP (`sendNow`, `send(day:preview:)`) send a whole day
///   at once. A whole-class send records the day's send.
/// - **Then each change goes live, one child at a time:** one made on this
///   device after 4 s of quiet, one synced in from another after 60 s (the
///   backstop for a phone that's offline or not signed in), each compared
///   with ParentLocker and saved only where it differs.
/// - **The guide's backstop:** arrival closed with no ParentLocker send
///   recorded within 60 s, and one of the guide's signed-in devices sends
///   the whole class and records it.
/// - **On launch and on the way back** the changes this device still owes go
///   once the first CloudKit import is in, so they're compared with fresh marks.
/// - Failures retry after 30 s, 2 min and 5 min, then wait. Nothing polls:
///   one task sleeps until the next thing is due, on an injected clock.
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
        var unsent: any ParentLockerUnsentStore = ParentLockerSavePolicy.current.allowsSaving
            ? ParentLockerDefaultsUnsentStore() : ParentLockerMemoryUnsentStore()
        var background: any ParentLockerBackgroundWork = ParentLockerSystemBackgroundWork()
        var isInForeground: @MainActor () -> Bool = { ParentLockerAppState.isInForeground() }
        /// Whether CloudKit imports will come: false for a stack without
        /// CloudKit, where the catch-up needn't wait for one.
        var importsExpected = true
        var calendar: Calendar = AppCalendar.shared
    }

    // MARK: - What the screens read (only the sync sets them)

    var status = ParentLockerStatus()
    /// A ParentLocker password is saved for the site (on this device, or synced to it).
    var isSignedIn = false
    /// The last whole-day plan or preview.
    var lastReport: ParentLockerReport?

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
    @ObservationIgnored var importedDue: Date?
    @ObservationIgnored var wholeClass: ParentLockerWholeClass?
    @ObservationIgnored var retry: (job: ParentLockerJob, due: Date)?
    @ObservationIgnored var awaitingImport = false
    /// The day the owed changes are for: today when they were made.
    @ObservationIgnored var owedDay: Date?
    /// The day the guide's backstop last went or was scheduled.
    @ObservationIgnored var backstopDay: Date?

    @ObservationIgnored var wakeTask: Task<Void, Never>?
    @ObservationIgnored var activeRun: Task<Result<ParentLockerReport, ParentLockerSendFailure>, Never>?
    @ObservationIgnored private var watcher: ParentLockerWatcher?
    @ObservationIgnored var holdsBackground = false

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

    deinit {
        wakeTask?.cancel()
    }

    // MARK: - Starting and stopping

    /// Starts following the class: reads the sign-in, picks up what this
    /// device still owes (sent once the first import is in), and watches
    /// `context`'s saves, CloudKit's imports and the app coming and going.
    /// Pass nil to watch nothing (tests drive the sync by hand).
    func start(watching context: NSManagedObjectContext?) {
        Self.current = self
        refreshSignIn()
        loadOwed()
        awaitingImport = dependencies.importsExpected
        if let context { watcher = ParentLockerWatcher(context: context, sync: self) }
        if !awaitingImport { releaseCatchUp() }
        refreshStatus()
    }

    /// Stops watching and drops anything scheduled (what's owed stays saved).
    func stop() {
        watcher = nil
        wakeTask?.cancel()
        wakeTask = nil
        if Self.current === self { Self.current = nil }
        updateBackgroundHold(force: false)
    }

    // MARK: - Close Arrival, Send Now, MCP

    /// Close Arrival & Send: the whole class goes once `undoWindow` has passed
    /// without `cancelCloseArrivalSend`. Changes made meanwhile wait for it.
    /// Today only; other days go through Send Now.
    /// On a device not signed in, the send waits for the sign-in sheet (and
    /// the guide's backstop covers it if nobody signs in).
    func closeArrivalSend(on day: Date, after undoWindow: TimeInterval = closeArrivalUndoWindow) {
        guard isToday(day) else { return }
        rollOwedDay(to: day)
        wholeClass = ParentLockerWholeClass(
            reason: .closeArrival, due: isSignedIn ? clock.now.addingTimeInterval(undoWindow) : nil
        )
        saveOwed()
        reschedule()
    }

    /// Close Arrival's Undo: the pending send doesn't go. ParentLocker can't
    /// take a mark back, so this is the last moment it can be stopped.
    func cancelCloseArrivalSend() {
        guard wholeClass?.reason == .closeArrival else { return }
        wholeClass = nil
        saveOwed()
        reschedule()
    }

    /// Send Now: the whole class for `day`, now. Records the day's send.
    @discardableResult
    func sendNow(day: Date) async -> ParentLockerStatus {
        await run(ParentLockerJob(day: day, children: nil, reason: .sendNow))
        return status
    }

    /// A whole day for MCP and the Debug preview: `preview` reads and plans
    /// only, whatever the method; otherwise it sends and records the send, as
    /// Send Now does. The failure says why in plain words.
    func send(day: Date, preview: Bool) async -> Result<ParentLockerReport, ParentLockerSendFailure> {
        await run(ParentLockerJob(day: day, children: nil, reason: .request, preview: preview))
    }

    // MARK: - Signing in and out

    /// The site the guide picked.
    var site: String { store.site }

    /// Signs in through ParentLocker's own form, out of sight, and keeps the
    /// sign-in (`completeSignIn`).
    func signIn(email: String, password: String) async throws {
        let credential = ParentLockerKeychain.Credential(
            email: email.trimmingCharacters(in: .whitespacesAndNewlines), password: password
        )
        let site = site
        let cookies = try await dependencies.signIn(credential, site)
        try await completeSignIn(credential, cookies: cookies, site: site)
    }

    /// Keeps a sign-in the site's form accepted: first proves the attendance
    /// page loads with these cookies, then saves the password (synced to the
    /// person's own devices) and the cookies (this device only), and sends
    /// anything owed. The password is saved only once ParentLocker took it,
    /// so a mistyped one never replaces a working one on the other devices.
    func completeSignIn(
        _ credential: ParentLockerKeychain.Credential, cookies: [ParentLockerCookie], site: String
    ) async throws {
        let secrets = dependencies.secrets
        try secrets.saveCookies(cookies, site: site)
        let transport = makeTransport(site: site, cookies: cookies)
        do {
            _ = try await transport.courses()
        } catch {
            try? secrets.deleteCookies(site: site)
            throw error
        }
        try secrets.savePassword(credential, site: site)
        Self.logger.info("ParentLocker: signed in")
        isSignedIn = true
        status.state = .idle
        status.details = nil
        if wholeClass != nil, wholeClass?.due == nil { wholeClass?.due = clock.now }
        releaseCatchUp()
        refreshStatus()
    }

    /// Sign Out: deletes the password everywhere it synced (so the person's
    /// other devices sign out on their next check) and this device's cookies.
    func signOut() {
        try? dependencies.secrets.deletePassword(site: site)
        Self.logger.info("ParentLocker: signed out")
        signedOutHere()
    }

    /// Reads whether a password is saved for the site. One deleted on another
    /// device (Sign Out there) takes this device's cookies with it.
    func refreshSignIn() {
        let site = site
        let hasPassword = (try? dependencies.secrets.hasPassword(site: site)) ?? false
        if !hasPassword {
            if isSignedIn { signedOutHere() } else { try? dependencies.secrets.deleteCookies(site: site) }
        }
        isSignedIn = hasPassword
    }

    /// Brings the line up to date with the day while nothing is under way:
    /// off, signed out, waiting for arrival, or as the last run left it (a
    /// run from another day says nothing about this one).
    func refreshStatus() {
        let state = store.day(today, withChildren: false)
        guard state.method == .parentLocker else { return status = ParentLockerStatus(state: .off) }
        guard isSignedIn else { return status = ParentLockerStatus(state: .signedOut) }
        let quiet: ParentLockerStatus.State = state.isAfter || !state.isSchoolDay ? .idle : .waitingForArrival
        let ranToday = status.lastSyncAt.map(isToday) ?? false
        switch status.state {
        case .off, .signedOut, .waitingForArrival, .idle:
            status.state = quiet
        case .upToDate, .previewed, .retrying, .gaveUp:
            if !ranToday { status = ParentLockerStatus(state: quiet) }
        default:
            break
        }
    }

    /// Signed out, here or by Sign Out on another device: this device's
    /// cookies go, and nothing is owed any more.
    func signedOutHere() {
        try? dependencies.secrets.deleteCookies(site: site)
        isSignedIn = false
        localChanges = [:]
        localDue = nil
        catchUpChildren = []
        importedChildren = []
        importedDue = nil
        retry = nil
        saveOwed()
        status = ParentLockerStatus(state: .signedOut)
        reschedule()
    }
}
