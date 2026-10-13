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
        if !holdsLiveUpdates {
            if let localDue { dues.append(localDue) }
            if let importedDue { dues.append(importedDue) }
        }
        return dues.min()
    }

    var holdsLiveUpdates: Bool {
        wholeClass?.reason == .closeArrival && wholeClass?.due != nil
    }

    /// Sleeps until `nextWake`, once. A run in progress reschedules when it ends.
    func reschedule() {
        wakeTask?.cancel()
        wakeTask = nil
        defer { updateBackgroundHold(force: false) }
        guard activeRun == nil, let wake = nextWake else { return }
        let clock = clock
        wakeTask = Task { [weak self] in
            do { try await clock.sleep(until: wake) } catch { return }
            await self?.runDue()
        }
    }

    /// Runs everything due now, one run at a time. Tests call it after moving the clock.
    func runDue() async {
        while activeRun == nil, let job = takeDueJob(at: clock.now) {
            await run(job)
        }
    }

    /// The run due at `now`, taken off the schedule: a retry, then a
    /// whole-class send (which covers every child owed), then the children
    /// whose waits are up.
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
            importedDue = nil
            let reason: ParentLockerJob.Reason = switch whole.reason {
            case .closeArrival: .closeArrival
            case .backstop: .backstop
            case .owed: .owed
            }
            return ParentLockerJob(day: day, children: nil, reason: reason)
        }
        guard !holdsLiveUpdates else { return nil }
        var children = Set<UUID>()
        if let due = localDue, due <= now {
            children.formUnion(localChanges.keys)
            localDue = nil
        }
        if let due = importedDue, due <= now {
            children.formUnion(importedChildren)
            importedChildren = []
            importedDue = nil
        }
        return children.isEmpty ? nil : ParentLockerJob(day: day, children: children, reason: .live)
    }

    /// Runs `job` once whatever is running has finished, then schedules what's next.
    @discardableResult
    func run(_ job: ParentLockerJob) async -> Result<ParentLockerReport, ParentLockerSendFailure> {
        while let running = activeRun { _ = await running.value }
        let task = Task { await self.perform(job) }
        activeRun = task
        updateBackgroundHold(force: true)
        let report = await task.value
        activeRun = nil
        reschedule()
        return report
    }

    /// Holds a background-task window while a run is going or a send is due
    /// within seconds (a local change, Close Arrival's), so a phone locked
    /// right after still sends.
    func updateBackgroundHold(force: Bool) {
        let wanted = force || activeRun != nil || localDue != nil
            || (wholeClass?.reason == .closeArrival && wholeClass?.due != nil)
        guard wanted != holdsBackground else { return }
        holdsBackground = wanted
        if wanted { dependencies.background.begin() } else { dependencies.background.end() }
    }

    // MARK: - Days

    var today: Date { dependencies.calendar.startOfDay(for: clock.now) }

    func isToday(_ day: Date) -> Bool { isSameDay(day, clock.now) }

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
            importedDue = nil
            wholeClass = nil
            retry = nil
        }
        owedDay = dependencies.calendar.startOfDay(for: day)
    }

    // MARK: - Owed, kept across launches

    func saveOwed() {
        guard let owedDay else { return dependencies.unsent.save(nil) }
        dependencies.unsent.save(ParentLockerUnsent(
            day: AppCalendar.dayID(owedDay),
            children: Set(localChanges.keys).union(catchUpChildren),
            wholeClass: wholeClass != nil
        ))
    }

    func loadOwed() {
        guard let saved = dependencies.unsent.load() else { return }
        guard saved.day == AppCalendar.dayID(today) else { return dependencies.unsent.save(nil) }
        owedDay = today
        catchUpChildren = saved.children
        if saved.wholeClass, wholeClass == nil { wholeClass = ParentLockerWholeClass(reason: .owed, due: nil) }
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
    enum Reason: Sendable, Equatable { case live, closeArrival, backstop, owed, sendNow, request }
    var day: Date
    /// Nil for the whole class.
    var children: Set<UUID>?
    var reason: Reason
    var preview = false
    /// Retries already made.
    var attempt = 0

    var isWholeClass: Bool { children == nil }
}

/// A whole-class send owed: why, and when it goes (nil: owed, waiting for the
/// next change, a return to the app or Send Now).
nonisolated struct ParentLockerWholeClass: Sendable, Equatable {
    enum Reason: Sendable, Equatable { case closeArrival, backstop, owed }
    var reason: Reason
    var due: Date?
}
