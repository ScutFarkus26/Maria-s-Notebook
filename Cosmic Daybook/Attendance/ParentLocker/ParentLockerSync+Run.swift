import Foundation
import OSLog

// One run of the sync: whether it may go, the classes' rosters, the plan,
// the saves, and what it leaves owed when something stops it.

extension ParentLockerSync {

    /// What a send for a day that hasn't come yet says.
    nonisolated static let notYetMessage =
        "That day hasn't come yet, so nothing went to ParentLocker. Send it on the day."

    /// What a send Close Arrival's Undo stopped says.
    nonisolated static let reopenedMessage = "Arrival was reopened, so nothing was sent."

    /// A whole day someone asked for (Send Now, MCP). Today's covers the
    /// changes noted before it, which it settles once it reaches ParentLocker.
    func askedJob(_ day: Date, reason: ParentLockerJob.Reason, preview: Bool = false) -> ParentLockerJob {
        var job = ParentLockerJob(day: day, children: nil, reason: reason, preview: preview)
        if isToday(day) { job.settles = importedChildren.union(earlyChanges).union(earlyLocal) }
        return job
    }

    /// Runs `job`: what it sent (or, previewing, would send), or why it
    /// didn't, and the status it ends on. Only a run for today sets the
    /// sync's own `status`; another day's tells only whoever asked. Under
    /// way, a whole-class run is still owed, should the app go meanwhile
    /// (`runningJob`, bug hunt 2026-11-05 #2), as what it is (review of the
    /// fixes, E6). `token`: today's Close Arrival & Send under way, which
    /// its Undo stops before the next class, leaving nothing owed (E1).
    func perform(_ job: ParentLockerJob, undo token: Int? = nil) async -> ParentLockerRunOutcome {
        let started = clock.now
        let isTodays = isToday(job.day)
        let day = store.day(job.day, withChildren: true)
        if isTodays { rememberMarks(day) }
        if let refusal = refusal(of: job, on: day) {
            return ParentLockerRunOutcome(
                result: .failure(refusal), status: isTodays ? status : ParentLockerStatus(state: .off)
            )
        }
        // The check after the due time goes once a day, sent or not.
        if job.reason == .deadline { backstopDay = job.day }
        runningJob = job.preview ? nil : job
        closeArrivalRuns.performing = token
        // A whole-class send under way makes today "after" here, and is
        // kept owed until it ends, though arrival closed here long before.
        if !job.preview, job.isWholeClass, isTodays {
            markArrivalClosed()
            saveOwed()
        }
        let previous = status
        if !job.preview, isTodays { status.state = .sending }
        defer { leaveSendingIfDayEnded(job, startedToday: isTodays) }
        do {
            let result = try await withTransport(site: day.site) { transport in
                try await self.sendPlan(job, day: day, transport: transport, undo: token)
            }
            runningJob = nil
            if closeArrivalRuns.isUndone(token) { return undoneRun(previous: previous) }
            let (report, ended) = finish(job, day: day, result: result, started: started, previous: previous)
            return ParentLockerRunOutcome(result: .success(report), status: ended)
        } catch {
            runningJob = nil
            if closeArrivalRuns.isUndone(token) { return undoneRun(after: error, previous: previous) }
            let failure = ParentLockerStatus.failure(for: error, lastSyncAt: previous.lastSyncAt)
            var ended = failure
            if !job.preview {
                ended = failed(job, error: error, failure: failure)
            } else if isTodays {
                status = previous
            }
            return ParentLockerRunOutcome(result: .failure(ParentLockerSendFailure(
                message: failure.message ?? ParentLockerError.unreachable.errorDescription ?? "",
                details: failure.details
            )), status: ended)
        }
    }

    /// A Close Arrival & Send its Undo stopped: nothing more goes, nothing is
    /// recorded, retried or owed, and the line is the reopened day's (E1).
    /// A sign-out it found still signs out.
    private func undoneRun(after error: Error? = nil, previous: ParentLockerStatus) -> ParentLockerRunOutcome {
        let stop = error as? ParentLockerSyncStop
        if stop == .signedOut { signedOutHere() }
        if stop == .passwordRefused { try? dependencies.secrets.deleteCookies(site: site) }
        status = ParentLockerStatus(state: .idle, problems: previous.problems, lastSyncAt: previous.lastSyncAt)
        refreshStatus()
        saveOwed()
        let message = closeArrivalBatchSent ? "Arrival was reopened, so the rest of the class wasn't sent." :
            Self.reopenedMessage
        return ParentLockerRunOutcome(result: .failure(ParentLockerSendFailure(message: message)), status: status)
    }

    /// A run of today's that ends on a new day: the line is the new day's,
    /// not Sending (bug hunt 2026-11-05 #24).
    private func leaveSendingIfDayEnded(_ job: ParentLockerJob, startedToday: Bool) {
        guard startedToday, !isToday(job.day), status.state == .sending else { return }
        status = ParentLockerStatus(state: .idle)
        refreshStatus()
    }

    // MARK: - May it go?

    /// The rules a run checks against the day as it is now: never a day that
    /// hasn't come yet (ParentLocker shows today's class list for one, and
    /// sending it would make that day "after" from midnight); ParentLocker
    /// picked (a preview reads either way); and for the sync's own runs
    /// today, a school day and past "after"; the backstops only on the
    /// guide's device while nothing is recorded, the one after the due time
    /// only once everyone is marked. A run that may not go drops the children
    /// it carried (the whole-class send at Close Arrival covers them) and
    /// says why.
    private func refusal(of job: ParentLockerJob, on day: ParentLockerDay) -> ParentLockerSendFailure? {
        if isAhead(job.day) {
            drop(job)
            return ParentLockerSendFailure(message: Self.notYetMessage)
        }
        if job.preview { return nil }
        guard day.method == .parentLocker else {
            drop(job)
            if isToday(job.day) { status = ParentLockerStatus(state: .off) }
            return ParentLockerSendFailure(
                message: "Attendance goes by email. Pick ParentLocker in Settings to send it there."
            )
        }
        return reasonRefusal(of: job, on: day)
    }

    /// The rules each kind of run adds.
    private func reasonRefusal(of job: ParentLockerJob, on day: ParentLockerDay) -> ParentLockerSendFailure? {
        switch job.reason {
        case .sendNow, .request:
            return nil
        case .closeArrival:
            // Arrival reopened another way before the send went, or Reset Day
            // (here or synced in) cleared every mark: arrival is open here again.
            if isAfter(day, on: job.day), day.anyoneMarked { return nil }
            if isToday(job.day), !day.sentToParentLocker { arrivalReopenedHere() }
            return ParentLockerSendFailure(message: "Arrival was reopened, so nothing was sent.")
        case .live, .owed:
            let after = isAfter(day, on: job.day)
            guard !isToday(job.day) || !day.isSchoolDay || !after else { return nil }
            if isToday(job.day), day.isSchoolDay { keepUntilAfter(job, marks: day.marks) } else { drop(job) }
            if !after { status.state = .waitingForArrival }
            return ParentLockerSendFailure(message: "Nothing goes to ParentLocker until arrival closes.")
        case .backstop, .deadline:
            return backstopRefusal(of: job, on: day)
        }
    }

    /// The guide's backstops go only from the guide's device, today, while
    /// nothing is recorded: after arrival closed, or after the due time once
    /// everyone is marked. A backstop that doesn't go leaves the day free for
    /// the next one: arrival may close again after an Undo. Changes made
    /// before "after" go by themselves once the day is.
    private func backstopRefusal(of job: ParentLockerJob, on day: ParentLockerDay) -> ParentLockerSendFailure? {
        let waiting = job.reason == .backstop ? day.arrivalClosed : day.isSchoolDay && day.everyoneMarked
        guard !isToday(job.day) || day.role != .leadGuide || day.sentToParentLocker || !waiting else { return nil }
        if job.reason == .backstop, let backstopDay, isSameDay(backstopDay, job.day) { self.backstopDay = nil }
        if isToday(job.day), isAfter(day, on: job.day) {
            releaseEarlyChanges(on: job.day, sent: day.sentToParentLocker)
        }
        return ParentLockerSendFailure(message: "The day was already sent, or isn't taken yet.")
    }

    private func drop(_ job: ParentLockerJob) {
        guard let children = job.children else { return }
        for child in children { localChanges[child] = nil }
        saveOwed()
    }

    /// Today's changes refused because the day isn't "after" here any more
    /// (Undo, Reopen Arrival): kept until it is again, as changes made
    /// before it are (review of the afternoon fixes, H4), this device's own
    /// with what's owed while they have a mark to send (`marks`).
    private func keepUntilAfter(_ job: ParentLockerJob, marks: [UUID: ParentLockerPlanner.DayMark]) {
        guard let children = job.children else { return }
        let own = children.subtracting(job.imported)
        for child in own { localChanges[child] = nil }
        keepEarlyLocal(own, marks: marks)
        earlyLocalDue = nil
        earlyChanges.formUnion(job.imported.subtracting(earlyLocal))
        saveOwed()
    }

    // MARK: - Sending

    /// Loads the classes that take daily attendance (another day's from that
    /// day's own page, which carries that day's report ids), plans, and
    /// (unless previewing) saves one class at a time. A class that won't
    /// load for now doesn't stop the others; the run then ends unfinished,
    /// so it's retried and not recorded (bug hunt 2026-11-05 #5), unless
    /// ParentLocker refused it today before: it then stands, named on the
    /// line, as a mark the school's page lacks does (review of the fixes,
    /// E7). Close Arrival's Undo stops it before its next class (E1).
    private func sendPlan(
        _ job: ParentLockerJob, day: ParentLockerDay, transport: any ParentLockerTransport, undo token: Int?
    ) async throws -> ParentLockerRunResult {
        let today = isToday(job.day)
        let listed = try await transport.courses(on: today ? nil : job.day)
        let (courses, leftAlone) = Self.coursesToLoad(listed, isToday: today)
        let (rosters, unread) = try await Self.readRosters(courses, day: job.day, transport: transport)
        var unfinished = unread
        var refused: [ParentLockerCourse] = []
        if today, !job.preview { (unfinished, refused) = standingRefusals(unread) }
        let matches = ParentLockerPlanner.match(children: day.children, rosters: rosters)
        let (only, leftToOthers) = childrenToCompare(job, matches: matches, rosters: rosters)
        let plan = ParentLockerPlanner.plan(
            children: day.children, marks: day.marks, rosters: rosters, only: only,
            day: job.day, calendar: dependencies.calendar, ownNotes: today ? ownNotes : [:]
        )
        let wasPreview = job.preview || !dependencies.policy.allowsSaving
        var conflicts: [String] = []
        var saved = 0
        if !wasPreview {
            for batch in plan.batches {
                if closeArrivalRuns.isUndone(token) { throw ParentLockerUndone() }
                if today { noteSending(batch, wholeClass: job.isWholeClass) }
                let reply = try await transport.save(batch: batch)
                saved += batch.entries.count
                if today { noteSaved(batch, reply: reply) }
                conflicts += reply.conflicts.filter { !$0.alreadyEqual }.map { conflict in
                    Self.conflictLine(conflict, batch: batch, rosters: rosters, day: day)
                }
            }
        }
        Self.logger.info("""
            ParentLocker: \(wasPreview ? "previewed" : "sent", privacy: .public) \
            \(plan.batches.map(\.entries.count).reduce(0, +), privacy: .public) changes \
            in \(plan.batches.count, privacy: .public) classes
            """)
        if let error = Self.classError(unfinished) { throw error }
        return ParentLockerRunResult(
            plan: plan, rosters: rosters, matches: matches, leftAlone: leftAlone,
            conflicts: conflicts, savedCount: saved, wasPreview: wasPreview, leftToOthers: leftToOthers,
            notExpected: today && Self.expectsNoAttendance(listed), refusedClasses: refused
        )
    }

    // MARK: - After a run

    /// Settles a run that reached ParentLocker: the day's send recorded if
    /// none is yet, what's owed, and the status. Returns the report and the
    /// status the run ends on (the sync's own only when the run is today's).
    private func finish(
        _ job: ParentLockerJob, day: ParentLockerDay, result: ParentLockerRunResult,
        started: Date, previous: ParentLockerStatus
    ) -> (report: ParentLockerReport, status: ParentLockerStatus) {
        let report = makeReport(job, day: day, result: result)
        if job.isWholeClass { lastReport = report }
        // An asked-for preview changes nothing here, the status included.
        if job.preview {
            if isToday(job.day) { status = previous }
            return (report, previous)
        }
        if result.notExpected { return (report, finishNotExpected(job, result: result, started: started)) }
        let matchedAny = result.matches.values.contains { if case .matched = $0 { true } else { false } }
        // A sync stopped meanwhile writes nothing: its context may be gone
        // with a rebuilt stack (bug hunt 2026-11-03 #1).
        if !result.wasPreview, !isStopped {
            if job.isWholeClass, matchedAny, recordsSend(job, day: day, result: result) {
                _ = store.recordSend(on: job.day)
            }
            if day.role == .leadGuide, !result.plan.newMatches.isEmpty {
                _ = store.writeMatches(result.plan.newMatches.mapValues { Optional($0) })
            }
        }
        settleOwed(after: job, startedAt: started, leftToOthers: result.leftToOthers)
        // Today's lines that stand, with the ones this run fixed gone (E7, W2).
        var problems = isToday(job.day)
            ? updateStanding(job, day: day, result: result) + result.conflicts : report.problems
        if job.isWholeClass, !matchedAny {
            problems.insert(
                "None of the class's children were found in ParentLocker. " +
                    "Check that you signed in with your school account.", at: 0
            )
        }
        let ended = ParentLockerStatus(
            state: result.wasPreview ? .previewed : endState(job, matchedAny: matchedAny),
            problems: problems, lastSyncAt: clock.now
        )
        if isToday(job.day) { status = ended }
        return (report, ended)
    }

    /// Every class ParentLocker lists today said it isn't expecting
    /// attendance: nothing went and nothing is recorded, the line says so
    /// (not "none of the class found" and "aren't matched"), and the day's
    /// reminder is withdrawn (bug hunt 2026-10-13 afternoon, M8).
    private func finishNotExpected(
        _ job: ParentLockerJob, result: ParentLockerRunResult, started: Date
    ) -> ParentLockerStatus {
        if !result.wasPreview, !isStopped { store.noteNotExpected(on: job.day) }
        settleOwed(after: job, startedAt: started)
        if isToday(job.day) { standing = ParentLockerStanding() }
        let ended = ParentLockerStatus(state: .notExpected, lastSyncAt: clock.now)
        if isToday(job.day) { status = ended }
        return ended
    }

    /// The day's send is recorded once, whatever sent it, so a day sent on
    /// time stays on time (a record synced in meanwhile counts). A send
    /// someone asked for (Send Now, the Shortcut, MCP) with children still
    /// unmarked sends the rest but doesn't count as the day's (bug hunt
    /// 2026-10-13 afternoon, M4). A backstop, or a retry, that found every
    /// child saved by someone else since leaves the record to them: theirs
    /// is on its way.
    private func recordsSend(_ job: ParentLockerJob, day: ParentLockerDay, result: ParentLockerRunResult) -> Bool {
        guard !store.day(job.day, withChildren: false).sentToParentLocker else { return false }
        if job.reason == .sendNow || job.reason == .request, !day.unmarkedChildren.isEmpty { return false }
        return !(job.comparesWithLastSeen && result.savedCount == 0 && !result.leftToOthers.isEmpty)
    }

    /// A run that didn't get through: retry what can be, owe the rest, and
    /// say so plainly. Returns the status it ends on; today's is the sync's.
    private func failed(_ job: ParentLockerJob, error: Error, failure: ParentLockerStatus) -> ParentLockerStatus {
        Self.logger.error("ParentLocker: a send didn't go (\(String(describing: error), privacy: .public))")
        let isTodays = isToday(job.day)
        var ended = failure
        if isTodays {
            // A run that didn't get through fixed nothing: today's lines stand (W2).
            ended.problems = todaysStanding
            status = ended
        }
        switch failure.state {
        case .retrying:
            guard retryLater(job) else {
                owe(job)
                ended.state = .gaveUp
                if isTodays { status.state = .gaveUp }
                return ended
            }
        case .signedOut:
            signedOutHere(keeping: job)
        case .passwordRefused:
            owe(job)
            try? dependencies.secrets.deleteCookies(site: site)
        default:
            owe(job)
        }
        // A send someone asked for, still owed, waits for the sign-in it
        // needs. Not once the sheet was closed without one: each change
        // takes the send owed and it fails again, and the sign-in opened
        // after every mark (review of the afternoon fixes).
        if isTodays, needsSignIn, wholeClass != nil, !signInDeclined,
           job.reason == .closeArrival || job.reason == .sendNow {
            awaitsSignIn = true
        }
        return ended
    }

    /// Schedules `job`'s next try, unless its tries have run out. Another
    /// day's has a slot of its own per day: it never takes today's place
    /// (bug hunt 2026-10-13 afternoon, L8), nor another day's (2026-11-05
    /// #1). Kept with what's owed across launches (#2).
    private func retryLater(_ job: ParentLockerJob) -> Bool {
        guard job.attempt < Self.retryWaits.count else { return false }
        var again = job
        again.attempt += 1
        let next = (job: again, due: clock.now.addingTimeInterval(Self.retryWaits[job.attempt]))
        if isToday(job.day) {
            keepRetry(next)
        } else {
            otherDayRetries[dependencies.calendar.startOfDay(for: job.day)] = next
        }
        saveOwed()
        return true
    }

    /// Today's retry. A live update's never takes the place of the class's
    /// own (it covers the update, and this device's changes stay owed); the
    /// class's own, taking the place of a Close Arrival & Send's, stays one,
    /// so its Undo still stops it (bug hunt 2026-11-05 #1), and taking a
    /// Send Now's, keeps its rule (review of the fixes, E4). A live update's
    /// taking another's place carries both's children (E10).
    func keepRetry(_ next: (job: ParentLockerJob, due: Date)) {
        guard let pending = retry, isSameDay(pending.job.day, next.job.day) else { return retry = next }
        guard pending.job.isWholeClass else {
            return retry = next.job.isWholeClass ? next : (next.job.merging(pending.job), next.due)
        }
        guard next.job.isWholeClass else { return }
        var kept = next
        kept.job.settles.formUnion(pending.job.settles)
        if pending.job.reason == .closeArrival {
            kept.job.reason = .closeArrival
        } else if pending.job.reason == .sendNow || pending.job.reason == .request, next.job.reason != .closeArrival {
            kept.job.reason = pending.job.reason
        }
        retry = kept
    }
}

/// Close Arrival's Undo came while its send was under way: no further class goes (E1).
private nonisolated struct ParentLockerUndone: Error {}
