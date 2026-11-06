import Foundation

// When each owed send goes: one task sleeps until the next one is due, runs
// go one at a time, and what a run settles or leaves owed for the day.

extension ParentLockerSync {

    // MARK: - Scheduling

    /// When the next thing is due. Today's whole-class send, due or waiting
    /// to retry, holds the live updates: it covers them.
    var nextWake: Date? {
        var dues = [retryWake, wholeClass?.due].compactMap(\.self) + otherDayRetries.values.map(\.due)
        if awaitingImport, let importWaitEnds { dues.append(importWaitEnds) }
        if !holdsLiveUpdates { dues += liveWakes }
        return dues.min()
    }

    /// When today's retry goes: a whole class's never before a new Close
    /// Arrival & Send could go, a second after its Undo (review of the
    /// 2026-11-05 fixes, E2), so the absences that Undo takes back don't
    /// reach ParentLocker with a Send Now's retry.
    private var retryWake: Date? {
        guard let retry else { return nil }
        guard retry.job.isWholeClass, let notBefore = closeArrivalNotBefore else { return retry.due }
        return max(retry.due, notBefore)
    }

    /// When the live updates and the guide's check after the due time are
    /// due (that check also takes a whole-class send owed, E3). Changes
    /// synced in whose class lists are still being read wait for them.
    private var liveWakes: [Date] {
        var dues: [Date] = []
        if let localDue { dues.append(localDue) }
        if let earlyLocalDue, !earlyLocal.isEmpty { dues.append(earlyLocalDue) }
        if let due = readyImported.compactMap({ importedDues[$0] }).min() { dues.append(due) }
        if wholeClass?.due == nil, let deadlineDue { dues.append(deadlineDue) }
        return dues
    }

    /// Today's whole-class send is due (Close Arrival's waiting out its Undo,
    /// one owed and released), or waits to retry: a live update meanwhile
    /// would take that retry's place, or go over it (bug hunt 2026-11-05 #1).
    /// The class's send covers the changes; this device's own stay owed until
    /// a send gets through. The guide's backstop holds nothing.
    var holdsLiveUpdates: Bool {
        if let whole = wholeClass, whole.reason != .backstop, whole.due != nil { return true }
        return retry.map { $0.job.isWholeClass && isToday($0.job.day) } ?? false
    }

    /// The changes synced in that can go: not those whose class lists are
    /// being read as they arrived (bug hunt 2026-10-13 afternoon, M5).
    var readyImported: Set<UUID> { importedChildren.subtracting(baselineWaiting) }

    /// When the first change synced in goes; nil with none waiting.
    var importedDue: Date? { importedDues.values.min() }

    /// Sleeps until `nextWake`, once. A run in progress reschedules when it
    /// ends; a stopped sync schedules nothing.
    func reschedule() {
        wakeTask?.cancel()
        wakeTask = nil
        defer {
            updateBackgroundHold(force: false)
            refreshCloseArrivalUnsent()
        }
        guard !isStopped, activeRun == nil, let wake = nextWake else { return }
        let clock = clock
        wakeTask = Task { [weak self] in
            do { try await clock.sleep(until: wake) } catch { return }
            await self?.runDue()
        }
    }

    /// Runs everything due now, one run at a time, then schedules what's
    /// next: a wake that found nothing to run (a new day dropped what was
    /// owed) still lets the background window go (review of the 2026-11-05
    /// fixes, E11). Tests call it after moving the clock.
    func runDue() async {
        // No import came in time: the catch-up goes without it.
        if awaitingImport, let ends = importWaitEnds, ends <= clock.now { importFinished() }
        while activeRun == nil, let job = takeDueJob(at: clock.now) {
            await run(job)
        }
        reschedule()
    }

    /// The run due at `now`, taken off the schedule: a retry (today's, then
    /// another day's), then a whole-class send, then the guide's check after
    /// the due time, then the children whose waits are up. Today's
    /// whole-class retry waits out a new Close Arrival's Undo, then goes with
    /// that Close Arrival & Send as one send (E2). The check after the due
    /// time takes a whole-class send owed, so one whose retries ran out isn't
    /// left until someone happens to change a mark (E3).
    func takeDueJob(at now: Date) -> ParentLockerJob? {
        rollOwedDay(to: now)
        if let pending = retry, pending.due <= now, !waitsOutUndo(pending.job, at: now) {
            retry = nil
            return withCloseArrival(pending.job, at: now)
        }
        if let pending = otherDayRetries.filter({ $0.value.due <= now }).min(by: { $0.value.due < $1.value.due }) {
            otherDayRetries[pending.key] = nil
            return pending.value.job
        }
        if let whole = wholeClass, let due = whole.due, due <= now {
            wholeClass = nil
            return wholeClassJob(whole.jobReason, attempt: whole.attempt)
        }
        guard !holdsLiveUpdates else { return nil }
        if wholeClass?.due == nil, let due = deadlineDue, due <= now {
            deadlineDue = nil
            guard let owed = wholeClass else { return wholeClassJob(.deadline) }
            // Once a day, as the check itself.
            wholeClass = nil
            backstopDay = today
            return wholeClassJob(owed.jobReason, attempt: owed.attempt)
        }
        return liveJob(at: now)
    }

    /// A whole-class retry due inside a new Close Arrival's Undo window (E2).
    private func waitsOutUndo(_ job: ParentLockerJob, at now: Date) -> Bool {
        guard job.isWholeClass, let notBefore = closeArrivalNotBefore else { return false }
        return now < notBefore
    }

    /// Today's whole-class retry, going as the Close Arrival & Send due with
    /// it: one send, which its Undo stops, covering both's changes (E2).
    private func withCloseArrival(_ job: ParentLockerJob, at now: Date) -> ParentLockerJob {
        guard job.isWholeClass, isToday(job.day), let whole = wholeClass, whole.reason == .closeArrival,
              let due = whole.due, due <= now else { return job }
        wholeClass = nil
        var merged = wholeClassJob(.closeArrival, attempt: whole.attempt)
        merged.settles.formUnion(job.settles)
        return merged
    }

    /// Today's whole class. The changes noted before it aren't dropped as it
    /// goes: it settles them once it reaches ParentLocker, and one refused
    /// (the day sent elsewhere since) leaves them to go by themselves (bug
    /// hunt 2026-10-13 afternoon, H4).
    func wholeClassJob(_ reason: ParentLockerJob.Reason, attempt: Int = 0) -> ParentLockerJob {
        var job = ParentLockerJob(day: today, children: nil, reason: reason, attempt: attempt)
        job.settles = importedChildren.union(earlyChanges).union(earlyLocal)
        return job
    }

    /// This device's changes whose 4 s are up (and its own from before
    /// "after" whose wait is), and those synced in whose own 60 s are, each
    /// carrying what this device had seen of them in ParentLocker or, with
    /// nothing seen, its mark here from before the change. A child this
    /// device changed too goes as its own change.
    private func liveJob(at now: Date) -> ParentLockerJob? {
        var job = ParentLockerJob(day: today, children: [], reason: .live)
        if let due = earlyLocalDue, due <= now {
            // Owed as this device's own from here on: kept until they reach ParentLocker.
            for child in earlyLocal where localChanges[child] == nil { localChanges[child] = now }
            job.children?.formUnion(earlyLocal)
            forgetEarlyLocal(earlyLocal)
        }
        if let due = localDue, due <= now {
            job.children?.formUnion(localChanges.keys)
            localDue = nil
        }
        let ready = readyImported.filter { (importedDues[$0] ?? .distantFuture) <= now }
        if !ready.isEmpty {
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
            importedDues[child] = nil
        }
    }

    /// Each of `children` synced in goes 60 s after it arrived, unless one
    /// of its waits is already running (bug hunt 2026-11-05 #19).
    func startImportedWaits(_ children: Set<UUID>) {
        let due = clock.now.addingTimeInterval(Self.importedWait)
        for child in children where importedDues[child] == nil { importedDues[child] = due }
    }

    /// Runs `job` once whatever is running has finished (another run, or a
    /// read of the class lists for changes synced in), then schedules what's next.
    /// Today's Close Arrival & Send is under way from the moment it's taken,
    /// the wait included, until it ends; an Undo meanwhile stops it before
    /// its next class (review of the 2026-11-05 fixes, E1).
    @discardableResult
    func run(_ job: ParentLockerJob) async -> ParentLockerRunOutcome {
        let token = coversCloseArrival(job) ? closeArrivalRuns.begin() : nil
        refreshUnderWay()
        defer {
            if let token { closeArrivalRuns.end(token) }
            refreshUnderWay()
        }
        while true {
            if activeRun != nil {
                await waitForActiveRun()
            } else if readingBaseline, let reading = baselineTask {
                await reading.value
            } else {
                break
            }
        }
        if closeArrivalRuns.isUndone(token) {
            reschedule()
            let failure = ParentLockerSendFailure(message: Self.reopenedMessage)
            return ParentLockerRunOutcome(result: .failure(failure), status: status)
        }
        let task = Task { await self.perform(job, undo: token) }
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
    /// right after still sends. Never once the sync is stopped, nor for
    /// changes the class's retry holds: its wait is minutes (bug hunt
    /// 2026-11-05 #1). A window iOS ended, or never gave, is asked for again
    /// (#21).
    func updateBackgroundHold(force: Bool) {
        if holdsBackground, !dependencies.background.isHeld { holdsBackground = false }
        let wholeClassSoon = wholeClass.map { $0.reason != .backstop && $0.due != nil } ?? false
        let wanted = !isStopped && (force || activeRun != nil || wholeClassSoon
            || (localDue != nil && !holdsLiveUpdates))
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
    /// `changing`: the children whose change, already saved, rolled it.
    func rollOwedDay(to day: Date, changing children: Set<UUID> = []) {
        if let owedDay, isSameDay(owedDay, day) { return }
        if owedDay != nil {
            localChanges = [:]
            localDue = nil
            catchUpChildren = []
            forgetImported(importedChildren)
            importedBefore = [:]
            earlyChanges = []
            forgetEarlyLocal(earlyLocal)
            knownMarks = nil
            wholeClass = nil
            retry = nil
            deadlineDue = nil
            arrivalClosedHere = false
            awaitsSignIn = false
            signInDeclined = false
        }
        // What ParentLocker held is a day's: none of it says anything about this one.
        lastSeen = [:]
        sending = [:]
        ownNotes = [:]
        standing = ParentLockerStanding()
        baselineRead = []
        closeArrivalBatchSent = false
        owedDay = dependencies.calendar.startOfDay(for: day)
        rememberNewDaysMarks(day, changing: children)
    }

    /// The new day's marks as they stand, for the changes synced in from now
    /// on (`importedBefore`), unless this device read them today already. A
    /// phone suspended over midnight never heard `.NSCalendarDayChanged`, so
    /// its first change of the day had nothing to measure by (review of the
    /// afternoon fixes, M5). The children whose change rolled the day count
    /// as unmarked before it: this device saw nothing of them today.
    private func rememberNewDaysMarks(_ day: Date, changing children: Set<UUID>) {
        guard isSignedIn, !(knownMarksDay.map { isSameDay($0, day) } ?? false) else { return }
        var marks = store.day(day, withChildren: true).marks
        for child in children { marks[child] = nil }
        knownMarks = marks
        knownMarksDay = dependencies.calendar.startOfDay(for: day)
    }

    // MARK: - Settled or owed (kept across launches: `saveOwed`)

    /// What a run that reached ParentLocker settles: the changes made before
    /// it started (one made since goes on its own), a whole-class send owed
    /// or waiting for a sign-in, what a whole-class send covered (changes
    /// synced in, or made before "after", noted before it was taken), and a
    /// retry it covers. This device's own changes from before "after" that
    /// it left to another device (`leftToOthers`, a backstop's) aren't
    /// covered: they still go as this device's own.
    func settleOwed(after job: ParentLockerJob, startedAt started: Date, leftToOthers: Set<UUID> = []) {
        if job.isWholeClass { otherDayRetries[dependencies.calendar.startOfDay(for: job.day)] = nil }
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
            forgetEarlyLocal(job.settles.subtracting(leftToOthers))
        }
        saveOwed()
    }

    /// Keeps a failed run's work for the next change, the return to the app
    /// or Send Now. This device's own changes stay owed anyway (they're
    /// cleared only on success); an imported one is left to its own device.
    /// A Close Arrival & Send stays one, so its Undo still stops it, and so
    /// does any other whole-class send that fails while one is still to go
    /// (bug hunt 2026-11-05 #1); the guide's backstop scheduled meanwhile
    /// becomes it, owed (review of the fixes, E8). A Send Now's keeps its
    /// rule (E4). Owed with nothing due to send it, the guide's check after
    /// the day's due time takes it (E3).
    func owe(_ job: ParentLockerJob) {
        guard job.isWholeClass, isToday(job.day), job.reason != .request || !job.preview else { return }
        let closeArrival = job.reason == .closeArrival || closeArrivalPending
        let owed = ParentLockerWholeClass(retrying: job)
        switch wholeClass?.reason {
        case nil:
            wholeClass = owed
        case .backstop? where closeArrival:
            // That backstop hasn't gone: the day stays open to the check after the due time.
            backstopDay = nil
            wholeClass = ParentLockerWholeClass(reason: .closeArrival, due: nil, attempt: 1)
        case .owed? where owed.reason == .sendNow:
            wholeClass?.reason = .sendNow
        default:
            break
        }
        if closeArrival, wholeClass?.reason == .owed || wholeClass?.reason == .sendNow {
            wholeClass?.reason = .closeArrival
        }
        if wholeClass?.due == nil { considerDeadline(store.day(job.day, withChildren: false), on: job.day) }
        saveOwed()
    }

    /// Waits up to `limit` for a run under way to end, so a stack rebuild
    /// doesn't take the stores off under a send that has reached ParentLocker
    /// but isn't recorded yet (bug hunt 2026-11-03 #1). Returns whether no
    /// run is going. Bounded like the wait for the share attacher: a save
    /// can hang on a poor network.
    func waitForRun(upTo limit: Duration) async -> Bool {
        let deadline = ContinuousClock.now + limit
        while activeRun != nil, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        return activeRun == nil
    }
}
