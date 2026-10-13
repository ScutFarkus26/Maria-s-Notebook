import Foundation

// When each owed send goes: one task sleeps until the next one is due, runs
// go one at a time, and what's owed is kept across launches for the day.

extension ParentLockerSync {

    // MARK: - Scheduling

    /// When the next thing is due. A Close Arrival send waiting out its
    /// Undo holds the live updates: it covers them.
    var nextWake: Date? {
        var dues = [retry?.due, otherDayRetry?.due, wholeClass?.due].compactMap(\.self)
        if awaitingImport, let importWaitEnds { dues.append(importWaitEnds) }
        if !holdsLiveUpdates { dues += liveWakes }
        return dues.min()
    }

    /// When the live updates and the guide's check after the due time are
    /// due. Changes synced in whose class lists are still being read wait
    /// for them.
    private var liveWakes: [Date] {
        var dues: [Date] = []
        if let localDue { dues.append(localDue) }
        if let importedDue, !readyImported.isEmpty { dues.append(importedDue) }
        if wholeClass == nil, let deadlineDue { dues.append(deadlineDue) }
        return dues
    }

    var holdsLiveUpdates: Bool {
        wholeClass?.reason == .closeArrival && wholeClass?.due != nil
    }

    /// The changes synced in that can go: not those whose class lists are
    /// being read as they arrived (bug hunt 2026-10-13 afternoon, M5).
    var readyImported: Set<UUID> { importedChildren.subtracting(baselineWaiting) }

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

    /// The run due at `now`, taken off the schedule: a retry (today's, then
    /// another day's), then a whole-class send, then the guide's check after
    /// the due time, then the children whose waits are up.
    func takeDueJob(at now: Date) -> ParentLockerJob? {
        rollOwedDay(to: now)
        if let pending = retry, pending.due <= now {
            retry = nil
            return pending.job
        }
        if let pending = otherDayRetry, pending.due <= now {
            otherDayRetry = nil
            return pending.job
        }
        if let whole = wholeClass, let due = whole.due, due <= now {
            wholeClass = nil
            return wholeClassJob(whole.jobReason, attempt: whole.attempt)
        }
        guard !holdsLiveUpdates else { return nil }
        if wholeClass == nil, let due = deadlineDue, due <= now {
            deadlineDue = nil
            return wholeClassJob(.deadline)
        }
        return liveJob(at: now)
    }

    /// Today's whole class. The changes noted before it aren't dropped as it
    /// goes: it settles them once it reaches ParentLocker, and one refused
    /// (the day sent elsewhere since) leaves them to go by themselves (bug
    /// hunt 2026-10-13 afternoon, H4).
    private func wholeClassJob(_ reason: ParentLockerJob.Reason, attempt: Int = 0) -> ParentLockerJob {
        var job = ParentLockerJob(day: today, children: nil, reason: reason, attempt: attempt)
        job.settles = importedChildren.union(earlyChanges)
        return job
    }

    /// This device's changes whose 4 s are up, and those synced in whose 60 s
    /// are, each carrying what this device had seen of them in ParentLocker
    /// or, with nothing seen, its mark here from before the change. A child
    /// this device changed too goes as its own change.
    private func liveJob(at now: Date) -> ParentLockerJob? {
        var job = ParentLockerJob(day: today, children: [], reason: .live)
        if let due = localDue, due <= now {
            job.children?.formUnion(localChanges.keys)
            localDue = nil
        }
        if let due = importedDue, due <= now {
            let ready = readyImported
            job.imported = ready.subtracting(localChanges.keys)
            job.importedBaseline = importedBaseline.filter { job.imported.contains($0.key) }
            job.importedBefore = importedBefore.filter { job.imported.contains($0.key) }
            job.children?.formUnion(ready)
            forgetImported(ready)
        }
        return job.children?.isEmpty == false ? job : nil
    }

    /// Changes synced in that went, or that a whole-class send covered.
    func forgetImported(_ children: Set<UUID>) {
        importedChildren.subtract(children)
        for child in children {
            importedBaseline[child] = nil
            importedBefore[child] = nil
        }
        if importedChildren.isEmpty { importedDue = nil }
    }

    /// Runs `job` once whatever is running has finished (another run, or a
    /// read of the class lists for changes synced in), then schedules what's next.
    @discardableResult
    func run(_ job: ParentLockerJob) async -> ParentLockerRunOutcome {
        while true {
            if activeRun != nil {
                await waitForActiveRun()
            } else if readingBaseline, let reading = baselineTask {
                await reading.value
            } else {
                break
            }
        }
        let task = Task { await self.perform(job) }
        activeRun = task
        updateBackgroundHold(force: true)
        let outcome = await task.value
        activeRun = nil
        reschedule()
        return outcome
    }

    /// Returns once no run is going. Awaiting a run that has finished
    /// returns at once, without letting its own caller clear `activeRun`:
    /// a waiter that only awaited again would spin on the main actor forever.
    func waitForActiveRun() async {
        while let running = activeRun {
            _ = await running.value
            if activeRun == running { await Task.yield() }
        }
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
    /// only by Send Now or MCP; another day's retry keeps its own slot).
    func rollOwedDay(to day: Date) {
        if let owedDay, isSameDay(owedDay, day) { return }
        if owedDay != nil {
            localChanges = [:]
            localDue = nil
            catchUpChildren = []
            forgetImported(importedChildren)
            importedBefore = [:]
            earlyChanges = []
            knownMarks = nil
            wholeClass = nil
            retry = nil
            deadlineDue = nil
            arrivalClosedHere = false
            awaitsSignIn = false
        }
        // What ParentLocker held is a day's: none of it says anything about this one.
        lastSeen = [:]
        baselineRead = []
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

    /// What this device still owes from before launch. A whole-class send
    /// goes as a retry, over only what this device sees in ParentLocker by
    /// then (`ParentLockerJob.comparesWithLastSeen`): the others may have
    /// sent the class meanwhile, with newer marks. One made with arrival
    /// closed here stays a Close Arrival & Send, which its Undo still stops.
    func loadOwed() {
        guard let saved = dependencies.unsent.load() else { return }
        guard saved.day == AppCalendar.dayID(today) else { return dependencies.unsent.save(nil) }
        owedDay = today
        catchUpChildren = saved.children
        arrivalClosedHere = saved.arrivalClosed
        if saved.wholeClass, wholeClass == nil {
            let reason: ParentLockerWholeClass.Reason = saved.arrivalClosed ? .closeArrival : .owed
            wholeClass = ParentLockerWholeClass(reason: reason, due: nil, attempt: 1)
        }
    }

    /// Signed out, here or by Sign Out on another device: this device's
    /// cookies go, and nothing is owed any more.
    func signedOutHere() {
        try? dependencies.secrets.deleteCookies(site: site)
        forgetRefusedPassword()
        isSignedIn = false
        signInNeedsYou = false
        localChanges = [:]
        localDue = nil
        catchUpChildren = []
        forgetImported(importedChildren)
        importedBefore = [:]
        earlyChanges = []
        lastSeen = [:]
        baselineRead = []
        deadlineDue = nil
        retry = nil
        otherDayRetry = nil
        saveOwed()
        status = ParentLockerStatus(state: .signedOut)
        reschedule()
    }

    /// What a run that reached ParentLocker settles: the changes made before
    /// it started (one made since goes on its own), a whole-class send owed
    /// or waiting for a sign-in, what a whole-class send covered (changes
    /// synced in, or made before "after", noted before it was taken), and a
    /// retry it covers.
    func settleOwed(after job: ParentLockerJob, startedAt started: Date) {
        if job.isWholeClass, let pending = otherDayRetry, isSameDay(pending.job.day, job.day) { otherDayRetry = nil }
        guard isToday(job.day) else { return }
        let settled = job.children ?? Set(localChanges.keys)
        for child in settled where (localChanges[child] ?? .distantFuture) <= started {
            localChanges[child] = nil
        }
        if job.isWholeClass {
            catchUpChildren = []
            // Nothing of this device's own left to wait 4 s for: the send covered it.
            if localChanges.isEmpty { localDue = nil }
            if wholeClass != nil, wholeClass?.due == nil {
                wholeClass = nil
                awaitsSignIn = false
            }
            if let pending = retry, isSameDay(pending.job.day, job.day) { retry = nil }
            forgetImported(job.settles)
            earlyChanges.subtract(job.settles)
        }
        saveOwed()
    }

    /// Keeps a failed run's work for the next change, the return to the app
    /// or Send Now. This device's own changes stay owed anyway (they're
    /// cleared only on success); an imported one is left to its own device.
    /// A Close Arrival & Send stays one, so its Undo still stops it.
    func owe(_ job: ParentLockerJob) {
        guard job.isWholeClass, isToday(job.day), job.reason != .request || !job.preview else { return }
        if wholeClass == nil { wholeClass = ParentLockerWholeClass(retrying: job) }
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

    /// Siri's undo of a Close Arrival made while the class's sync isn't
    /// running: the whole-class send kept owed for `day`, and its "arrival
    /// closed", are taken back, so a later sign-in never sends a reopened
    /// class (bug hunt 2026-10-13 afternoon, H2).
    nonisolated static func cancelOwedCloseArrivalSend(on day: Date, in unsent: any ParentLockerUnsentStore) {
        guard var owed = unsent.load(), owed.day == AppCalendar.dayID(day) else { return }
        owed.wholeClass = false
        owed.arrivalClosed = false
        unsent.save(owed.isEmpty ? nil : owed)
    }

    /// The children on `day`'s roll with no mark yet, as the class reads them
    /// ("Maya S"), for a screen or the Shortcut to ask about before a send:
    /// a send goes without them and doesn't count as the day's (bug hunt
    /// 2026-10-13 afternoon, M4). The guide's "Not matched" children never
    /// go to ParentLocker, so they aren't asked about.
    func unmarkedNames(on day: Date) -> [String] {
        store.day(day, withChildren: true).unmarkedNames
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
    /// what this device had seen of them in ParentLocker when it arrived, or
    /// with nothing seen, their mark here from before the change.
    var imported: Set<UUID> = []
    var importedBaseline: [UUID: ParentLockerSeen] = [:]
    var importedBefore: [UUID: ParentLockerPlanner.DayMark?] = [:]
    /// For a whole-class send: the changes synced in, or made before
    /// "after", it covers once it reaches ParentLocker.
    var settles: Set<UUID> = []

    var isWholeClass: Bool { children == nil }

    /// Goes only over what this device last saw of each child in
    /// ParentLocker, leaving one saved since to the device that saved it: the
    /// guide's backstops, a whole-class retry and a whole-class send owed
    /// from before, which may come from a device that hasn't caught up (bug
    /// hunt 2026-10-13 afternoon, H5).
    var comparesWithLastSeen: Bool {
        switch reason {
        case .backstop, .deadline, .owed: true
        default: isWholeClass && attempt > 0
        }
    }
}
