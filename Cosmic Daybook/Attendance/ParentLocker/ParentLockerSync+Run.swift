import Foundation
import OSLog

// One run of the sync: whether it may go, the sign-in (signing back in by
// itself only in front, and never with a password ParentLocker refused or
// while ParentLocker wants a person to sign in), the classes' rosters, the
// plan, the saves, and what it leaves owed when something stops it.

extension ParentLockerSync {

    /// What a send for a day that hasn't come yet says.
    nonisolated static let notYetMessage =
        "That day hasn't come yet, so nothing went to ParentLocker. Send it on the day."

    /// Runs `job`: what it sent (or, previewing, would send), or why it
    /// didn't, and the status it ends on. Only a run for today sets the
    /// sync's own `status`; another day's tells only whoever asked.
    func perform(_ job: ParentLockerJob) async -> ParentLockerRunOutcome {
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
        // A whole-class send under way makes today "after" here.
        if !job.preview, job.isWholeClass, isTodays { markArrivalClosed() }
        let previous = status
        if !job.preview, isTodays { status.state = .sending }
        do {
            let result = try await withTransport(site: day.site) { transport in
                try await self.sendPlan(job, day: day, transport: transport)
            }
            let (report, ended) = finish(job, day: day, result: result, started: started, previous: previous)
            return ParentLockerRunOutcome(result: .success(report), status: ended)
        } catch {
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

    // MARK: - Signing in

    /// Runs `body` with a transport carrying the saved cookies. Before
    /// anything, the password must still be there (Sign Out on another
    /// device removes it). With no cookies, or when the site has signed this
    /// device out, it signs in again with the saved password and runs
    /// `body` once more, but only in front.
    private func withTransport<T>(
        site: String, _ body: (any ParentLockerTransport) async throws -> T
    ) async throws -> T {
        let secrets = dependencies.secrets
        let cookies: [ParentLockerCookie]
        do {
            guard try secrets.hasPassword(site: site) else { throw ParentLockerSyncStop.signedOut }
            cookies = try secrets.cookies(site: site)
        } catch let error as ParentLockerKeychain.KeychainError {
            Self.logger.error("ParentLocker: the keychain refused (\(String(describing: error), privacy: .public))")
            throw ParentLockerSyncStop.keychain
        }
        if cookies.isEmpty {
            return try await body(makeTransport(site: site, cookies: try await signInAgain(site: site)))
        }
        do {
            return try await body(makeTransport(site: site, cookies: cookies))
        } catch ParentLockerError.signedOut {
            Self.logger.info("ParentLocker: signed out by the site; signing in again")
            return try await body(makeTransport(site: site, cookies: try await signInAgain(site: site)))
        }
    }

    /// Signs in with the saved password through the site's form, out of
    /// sight, and keeps the new cookies. Never with a password ParentLocker
    /// refused: that one waits until a new one is saved, here or on another
    /// of the person's devices, so the school's site doesn't see it again and
    /// again. Never while ParentLocker wants a person at its sign-in (new
    /// terms, a reset) either: only a sign-in through the sheet, or a newer
    /// password saved on another of the person's devices, clears that (bug
    /// hunt 2026-10-13 afternoon, M9). Only in front: the web view stalls in
    /// the background.
    private func signInAgain(site: String) async throws -> [ParentLockerCookie] {
        let credential: ParentLockerKeychain.Credential?
        let saved: Date?
        do {
            credential = try dependencies.secrets.credential(site: site)
            saved = try dependencies.secrets.passwordModified(site: site)
        } catch {
            throw ParentLockerSyncStop.keychain
        }
        guard let credential else { throw ParentLockerSyncStop.signedOut }
        let password = saved ?? .distantPast
        guard dependencies.refusals.refused(site: site) != password else {
            savedPasswordRefused = true
            throw ParentLockerSyncStop.passwordRefused
        }
        if signInNeedsYou, needsYouPassword != password { signInNeedsYou = false }
        guard !signInNeedsYou else { throw ParentLockerSyncStop.needsYou }
        guard dependencies.isInForeground() else { throw ParentLockerSyncStop.notSentYet }
        let cookies: [ParentLockerCookie]
        do {
            cookies = try await dependencies.signIn(credential, site)
        } catch let error as ParentLockerSignInError {
            if error == .passwordRefused {
                Self.logger.error("ParentLocker: the saved password was refused; it won't be tried again")
                dependencies.refusals.setRefused(password, site: site)
                savedPasswordRefused = true
            } else if error == .needsYou {
                Self.logger.error("ParentLocker: the sign-in wants a person; it won't be tried again by itself")
                signInNeedsYou = true
                needsYouPassword = password
            }
            throw error.syncError
        }
        forgetRefusedPassword()
        try? dependencies.secrets.saveCookies(cookies, site: site)
        return cookies
    }

    // MARK: - Match Names

    /// The rosters of the classes that take daily attendance on `day`, for
    /// Match Names: read only, signing in again if needed.
    func loadRosters(day: Date) async throws -> [ParentLockerRoster] {
        let today = isToday(day)
        return try await withTransport(site: site) { transport in
            var rosters: [ParentLockerRoster] = []
            for course in Self.coursesToLoad(try await transport.courses(on: today ? nil : day), isToday: today).load {
                rosters.append(try await transport.roster(course: course, date: day))
            }
            return rosters
        }
    }

    // MARK: - Sending

    /// Loads the classes that take daily attendance (another day's from that
    /// day's own page, which carries that day's report ids), plans, and
    /// (unless previewing) saves one class at a time.
    private func sendPlan(
        _ job: ParentLockerJob, day: ParentLockerDay, transport: any ParentLockerTransport
    ) async throws -> ParentLockerRunResult {
        let today = isToday(job.day)
        let listed = try await transport.courses(on: today ? nil : job.day)
        let (courses, leftAlone) = Self.coursesToLoad(listed, isToday: today)
        var rosters: [ParentLockerRoster] = []
        for course in courses {
            rosters.append(try await transport.roster(course: course, date: job.day))
        }
        let matches = ParentLockerPlanner.match(children: day.children, rosters: rosters)
        let (only, leftToOthers) = childrenToCompare(job, matches: matches, rosters: rosters)
        let plan = ParentLockerPlanner.plan(
            children: day.children, marks: day.marks, rosters: rosters, only: only,
            day: job.day, calendar: dependencies.calendar
        )
        let wasPreview = job.preview || !dependencies.policy.allowsSaving
        var conflicts: [String] = []
        var saved = 0
        if !wasPreview {
            for batch in plan.batches {
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
        return ParentLockerRunResult(
            plan: plan, rosters: rosters, matches: matches, leftAlone: leftAlone,
            conflicts: conflicts, savedCount: saved, wasPreview: wasPreview, leftToOthers: leftToOthers,
            notExpected: today && Self.expectsNoAttendance(listed)
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
        if !result.wasPreview {
            if job.isWholeClass, matchedAny, recordsSend(job, day: day, result: result) {
                _ = store.recordSend(on: job.day)
            }
            if day.role == .leadGuide, !result.plan.newMatches.isEmpty {
                _ = store.writeMatches(result.plan.newMatches.mapValues { Optional($0) })
            }
        }
        settleOwed(after: job, startedAt: started, leftToOthers: result.leftToOthers)
        var problems = report.problems
        if job.isWholeClass, !matchedAny {
            problems.insert(
                "None of the class's children were found in ParentLocker. " +
                    "Check that you signed in with your school account.", at: 0
            )
        }
        let ended = ParentLockerStatus(
            state: result.wasPreview ? .previewed : (matchedAny || !job.isWholeClass ? .upToDate : .idle),
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
        if !result.wasPreview { store.noteNotExpected(on: job.day) }
        settleOwed(after: job, startedAt: started)
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
        if isTodays { status = failure }
        switch failure.state {
        case .retrying:
            guard job.attempt < Self.retryWaits.count else {
                owe(job)
                ended.state = .gaveUp
                if isTodays { status.state = .gaveUp }
                return ended
            }
            var again = job
            again.attempt += 1
            let next = (again, clock.now.addingTimeInterval(Self.retryWaits[job.attempt]))
            // Another day's retry has its own slot: it never takes today's
            // place (bug hunt 2026-10-13 afternoon, L8).
            if isTodays { retry = next } else { otherDayRetry = next }
        case .signedOut:
            signedOutHere()
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
}
