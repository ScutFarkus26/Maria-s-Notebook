import Foundation

// When each owed send goes: one task sleeps until the next one is due, runs
// go one at a time, and what's owed is kept across launches for the day.

extension ParentLockerSync {

    // MARK: - Scheduling

    /// When the next thing is due. A Close Arrival send waiting out its
    /// Undo holds the live updates: it covers them.
    var nextWake: Date? {
        var dues: [Date] = []
        if let retry { dues.append(retry.due) }
        if let due = wholeClass?.due { dues.append(due) }
        if awaitingImport, let importWaitEnds { dues.append(importWaitEnds) }
        if !holdsLiveUpdates {
            if let localDue { dues.append(localDue) }
            if let importedDue { dues.append(importedDue) }
            if wholeClass == nil, let deadlineDue { dues.append(deadlineDue) }
        }
        return dues.min()
    }

    var holdsLiveUpdates: Bool {
        wholeClass?.reason == .closeArrival && wholeClass?.due != nil
    }

    /// Sleeps until `nextWake`, once. A run in progress reschedules when it
    /// ends; a stopped sync schedules nothing.
    func reschedule() {
        wakeTask?.cancel()
        wakeTask = nil
        defer { updateBackgroundHold(force: false) }
        guard !isStopped, activeRun == nil, let wake = nextWake else { return }
        let clock = clock
        wakeTask = Task { [weak self] in
            do { try await clock.sleep(until: wake) } catch { return }
            await self?.runDue()
        }
    }

    /// Runs everything due now, one run at a time. Tests call it after moving the clock.
    func runDue() async {
        // No import came in time: the catch-up goes without it.
        if awaitingImport, let ends = importWaitEnds, ends <= clock.now { importFinished() }
        while activeRun == nil, let job = takeDueJob(at: clock.now) {
            await run(job)
        }
    }

    /// The run due at `now`, taken off the schedule: a retry, then a
    /// whole-class send (which covers every child owed), then the guide's
    /// check after the due time, then the children whose waits are up (those
    /// synced in carrying what this device had seen of them).
    func takeDueJob(at now: Date) -> ParentLockerJob? {
        rollOwedDay(to: now)
        let day = today
        if let pending = retry, pending.due <= now {
            retry = nil
            return pending.job
        }
        if let whole = wholeClass, let due = whole.due, due <= now {
            wholeClass = nil
            localDue = nil
            importedChildren = []
            importedBaseline = [:]
            importedDue = nil
            let reason: ParentLockerJob.Reason = switch whole.reason {
            case .closeArrival: .closeArrival
            case .backstop: .backstop
            case .owed: .owed
            }
            return ParentLockerJob(day: day, children: nil, reason: reason)
        }
        guard !holdsLiveUpdates else { return nil }
        if wholeClass == nil, let due = deadlineDue, due <= now {
            deadlineDue = nil
            return ParentLockerJob(day: day, children: nil, reason: .deadline)
        }
        var job = ParentLockerJob(day: day, children: [], reason: .live)
        if let due = localDue, due <= now {
            job.children?.formUnion(localChanges.keys)
            localDue = nil
        }
        if let due = importedDue, due <= now {
            // A child this device changed too goes as its own change.
            job.imported = importedChildren.subtracting(localChanges.keys)
            job.importedBaseline = importedBaseline.filter { job.imported.contains($0.key) }
            job.children?.formUnion(importedChildren)
            importedChildren = []
            importedBaseline = [:]
            importedDue = nil
        }
        return job.children?.isEmpty == false ? job : nil
    }

    /// Runs `job` once whatever is running has finished, then schedules what's next.
    @discardableResult
    func run(_ job: ParentLockerJob) async -> ParentLockerRunOutcome {
        while let running = activeRun { _ = await running.value }
        let task = Task { await self.perform(job) }
        activeRun = task
        updateBackgroundHold(force: true)
        let outcome = await task.value
        activeRun = nil
        reschedule()
        return outcome
    }

    /// Holds a background-task window while a run is going or a send is due
    /// within seconds (a local change, Close Arrival's), so a phone locked
    /// right after still sends. Never once the sync is stopped.
    func updateBackgroundHold(force: Bool) {
        let wanted = !isStopped && (force || activeRun != nil || localDue != nil
            || (wholeClass?.reason == .closeArrival && wholeClass?.due != nil))
        guard wanted != holdsBackground else { return }
        holdsBackground = wanted
        if wanted { dependencies.background.begin() } else { dependencies.background.end() }
    }

    // MARK: - Days

    var today: Date { dependencies.calendar.startOfDay(for: clock.now) }

    func isToday(_ day: Date) -> Bool { isSameDay(day, clock.now) }

    /// A day that hasn't come yet.
    func isAhead(_ day: Date) -> Bool { dependencies.calendar.startOfDay(for: day) > today }

    func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        dependencies.calendar.isDate(lhs, inSameDayAs: rhs)
    }

    /// What's owed is for one day: a new day drops yesterday's (past days go
    /// only by Send Now or MCP).
    func rollOwedDay(to day: Date) {
        if let owedDay, isSameDay(owedDay, day) { return }
        if owedDay != nil {
            localChanges = [:]
            localDue = nil
            catchUpChildren = []
            importedChildren = []
            importedBaseline = [:]
            importedDue = nil
            wholeClass = nil
            retry = nil
            deadlineDue = nil
            arrivalClosedHere = false
        }
        // What ParentLocker held is a day's: none of it says anything about this one.
        lastSeen = [:]
        owedDay = dependencies.calendar.startOfDay(for: day)
    }

    // MARK: - Owed, kept across launches

    func saveOwed() {
        guard let owedDay else { return dependencies.unsent.save(nil) }
        dependencies.unsent.save(ParentLockerUnsent(
            day: AppCalendar.dayID(owedDay),
            children: Set(localChanges.keys).union(catchUpChildren),
            wholeClass: wholeClass != nil,
            arrivalClosed: arrivalClosedHere
        ))
    }

    func loadOwed() {
        guard let saved = dependencies.unsent.load() else { return }
        guard saved.day == AppCalendar.dayID(today) else { return dependencies.unsent.save(nil) }
        owedDay = today
        catchUpChildren = saved.children
        arrivalClosedHere = saved.arrivalClosed
        if saved.wholeClass, wholeClass == nil { wholeClass = ParentLockerWholeClass(reason: .owed, due: nil) }
    }

    /// What a run that reached ParentLocker settles: the changes made before
    /// it started (one made since goes on its own), a whole-class send owed,
    /// and a retry it covers.
    func settleOwed(after job: ParentLockerJob, startedAt started: Date) {
        guard isToday(job.day) else { return }
        let settled = job.children ?? Set(localChanges.keys)
        for child in settled where (localChanges[child] ?? .distantFuture) <= started {
            localChanges[child] = nil
        }
        if job.isWholeClass {
            catchUpChildren = []
            if wholeClass?.reason == .owed { wholeClass = nil }
            if let pending = retry, isSameDay(pending.job.day, job.day) { retry = nil }
        }
        saveOwed()
    }

    /// Keeps a failed run's work for the next change, the return to the app
    /// or Send Now. This device's own changes stay owed anyway (they're
    /// cleared only on success); an imported one is left to its own device.
    func owe(_ job: ParentLockerJob) {
        guard job.isWholeClass, isToday(job.day), job.reason != .request || !job.preview else { return }
        if wholeClass == nil { wholeClass = ParentLockerWholeClass(reason: .owed, due: nil) }
        saveOwed()
    }

    /// Where what's owed is kept: the app's preferences in a build that
    /// saves, memory otherwise (`ParentLockerDefaultsUnsentStore`).
    nonisolated static func defaultUnsentStore() -> any ParentLockerUnsentStore {
        ParentLockerSavePolicy.current.allowsSaving
            ? ParentLockerDefaultsUnsentStore() : ParentLockerMemoryUnsentStore()
    }

    /// Close Arrival & Send made while the class's sync isn't running (Siri,
    /// with the app launched for the intent alone): the whole-class send is
    /// kept owed for `day`, with arrival closed, and the sync sends it when
    /// it starts and is signed in.
    nonisolated static func oweCloseArrivalSend(on day: Date, in unsent: any ParentLockerUnsentStore) {
        let id = AppCalendar.dayID(day)
        var owed = unsent.load().flatMap { $0.day == id ? $0 : nil }
            ?? ParentLockerUnsent(day: id, children: [], wholeClass: false)
        owed.wholeClass = true
        owed.arrivalClosed = true
        unsent.save(owed)
    }

    func makeTransport(site: String, cookies: [ParentLockerCookie]) -> any ParentLockerTransport {
        let secrets = dependencies.secrets
        return dependencies.makeTransport(site, cookies) { changed in
            try? secrets.saveCookies(changed, site: site)
        }
    }
}

/// One run of the sync: the whole class or some children, for a day.
nonisolated struct ParentLockerJob: Sendable, Equatable {
    /// `.deadline` is the guide's check after the day's due time.
    enum Reason: Sendable, Equatable { case live, closeArrival, backstop, deadline, owed, sendNow, request }
    var day: Date
    /// Nil for the whole class.
    var children: Set<UUID>?
    var reason: Reason
    var preview = false
    /// Retries already made.
    var attempt = 0
    /// Of `children`, those whose change synced in from another device, and
    /// what this device had seen of them in ParentLocker when it arrived.
    var imported: Set<UUID> = []
    var importedBaseline: [UUID: ParentLockerSeen] = [:]

    var isWholeClass: Bool { children == nil }
}

/// What one run found and did.
struct ParentLockerRunResult {
    let plan: ParentLockerPlanner.Plan
    let rosters: [ParentLockerRoster]
    let matches: [UUID: ParentLockerPlanner.Match]
    let leftAlone: [String]
    let conflicts: [String]
    let savedCount: Int
    let wasPreview: Bool
    /// Children left to another device, which saved them in ParentLocker
    /// since this device last looked.
    let leftToOthers: Set<UUID>
}

/// How one run went: what it sent (or why not), and the status it ends on.
nonisolated struct ParentLockerRunOutcome: Sendable {
    let result: Result<ParentLockerReport, ParentLockerSendFailure>
    let status: ParentLockerStatus
}

/// A whole-class send owed: why, and when it goes (nil: owed, waiting for the
/// next change, a return to the app or Send Now).
nonisolated struct ParentLockerWholeClass: Sendable, Equatable {
    enum Reason: Sendable, Equatable { case closeArrival, backstop, owed }
    var reason: Reason
    var due: Date?
}
