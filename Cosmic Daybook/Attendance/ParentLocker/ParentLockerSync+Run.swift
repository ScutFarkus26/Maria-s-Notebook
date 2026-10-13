import Foundation
import OSLog

// One run of the sync: whether it may go, the sign-in (signing back in by
// itself only in front), the classes' rosters, the plan, the saves, and what
// it leaves owed when something stops it.

/// What one run found and did.
private struct ParentLockerRunResult {
    let plan: ParentLockerPlanner.Plan
    let rosters: [ParentLockerRoster]
    let matches: [UUID: ParentLockerPlanner.Match]
    let leftAlone: [String]
    let conflicts: [String]
    let savedCount: Int
    let wasPreview: Bool
}

extension ParentLockerSync {

    /// Runs `job`: what it sent (or, previewing, would send), or why it didn't.
    func perform(_ job: ParentLockerJob) async -> Result<ParentLockerReport, ParentLockerSendFailure> {
        let started = clock.now
        let day = store.day(job.day, withChildren: true)
        if let refusal = refusal(of: job, on: day) { return .failure(refusal) }
        // The check after the due time goes once a day, sent or not.
        if job.reason == .deadline { backstopDay = job.day }
        let previous = status
        if !job.preview { status.state = .sending }
        do {
            let result = try await withTransport(site: day.site) { transport in
                try await self.sendPlan(job, day: day, transport: transport)
            }
            return .success(finish(job, day: day, result: result, started: started, previous: previous))
        } catch {
            let failure = ParentLockerStatus.failure(for: error, lastSyncAt: previous.lastSyncAt)
            if job.preview { status = previous } else { failed(job, error: error, failure: failure) }
            return .failure(ParentLockerSendFailure(
                message: failure.message ?? ParentLockerError.unreachable.errorDescription ?? "",
                details: failure.details
            ))
        }
    }

    // MARK: - May it go?

    /// The rules a run checks against the day as it is now: ParentLocker
    /// picked (a preview reads either way), and for the sync's own runs today,
    /// a school day and past "after"; the backstops only on the guide's device
    /// while nothing is recorded, the one after the due time only once
    /// everyone is marked. A run that may not go drops the children it
    /// carried (the whole-class send at Close Arrival covers them) and says why.
    private func refusal(of job: ParentLockerJob, on day: ParentLockerDay) -> ParentLockerSendFailure? {
        if job.preview { return nil }
        guard day.method == .parentLocker else {
            drop(job)
            status = ParentLockerStatus(state: .off)
            return ParentLockerSendFailure(
                message: "Attendance goes by email. Pick ParentLocker in Settings to send it there."
            )
        }
        switch job.reason {
        case .sendNow, .request:
            return nil
        case .closeArrival:
            // Arrival reopened another way before the send went.
            guard !day.isAfter else { return nil }
            return ParentLockerSendFailure(message: "Arrival was reopened, so nothing was sent.")
        case .live, .owed:
            guard !isToday(job.day) || !day.isSchoolDay || !day.isAfter else { return nil }
            drop(job)
            if !day.isAfter { status.state = .waitingForArrival }
            return ParentLockerSendFailure(message: "Nothing goes to ParentLocker until arrival closes.")
        case .backstop, .deadline:
            return backstopRefusal(of: job, on: day)
        }
    }

    /// The guide's backstops go only from the guide's device, today, while
    /// nothing is recorded: after arrival closed, or after the due time once
    /// everyone is marked.
    private func backstopRefusal(of job: ParentLockerJob, on day: ParentLockerDay) -> ParentLockerSendFailure? {
        let waiting = job.reason == .backstop ? day.arrivalClosed : day.isSchoolDay && day.everyoneMarked
        guard !isToday(job.day) || day.role != .leadGuide || day.sentToParentLocker || !waiting else { return nil }
        return ParentLockerSendFailure(message: "The day was already sent, or isn't taken yet.")
    }

    private func drop(_ job: ParentLockerJob) {
        guard let children = job.children else { return }
        for child in children { localChanges[child] = nil }
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
    /// sight, and keeps the new cookies. Only in front: the web view stalls
    /// in the background.
    private func signInAgain(site: String) async throws -> [ParentLockerCookie] {
        guard dependencies.isInForeground() else { throw ParentLockerSyncStop.notSentYet }
        let credential: ParentLockerKeychain.Credential?
        do {
            credential = try dependencies.secrets.credential(site: site)
        } catch {
            throw ParentLockerSyncStop.keychain
        }
        guard let credential else { throw ParentLockerSyncStop.signedOut }
        let cookies: [ParentLockerCookie]
        do {
            cookies = try await dependencies.signIn(credential, site)
        } catch let error as ParentLockerSignInError {
            throw error.syncError
        }
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
            for course in Self.coursesToLoad(try await transport.courses(on: nil), isToday: today).load {
                rosters.append(try await transport.roster(course: course, date: day))
            }
            return rosters
        }
    }

    // MARK: - Sending

    /// Loads the classes that take daily attendance, plans, and (unless
    /// previewing) saves one class at a time.
    private func sendPlan(
        _ job: ParentLockerJob, day: ParentLockerDay, transport: any ParentLockerTransport
    ) async throws -> ParentLockerRunResult {
        let (courses, leftAlone) = Self.coursesToLoad(try await transport.courses(on: nil), isToday: isToday(job.day))
        var rosters: [ParentLockerRoster] = []
        for course in courses {
            rosters.append(try await transport.roster(course: course, date: job.day))
        }
        let matches = ParentLockerPlanner.match(children: day.children, rosters: rosters)
        let only = childrenToCompare(job, matches: matches, rosters: rosters)
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
                if isToday(job.day) { noteSaved(batch, reply: reply) }
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
            conflicts: conflicts, savedCount: saved, wasPreview: wasPreview
        )
    }

    /// The children `job` compares, once today's rosters are in (which also
    /// become what this device last saw): an imported change whose child
    /// ParentLocker no longer holds as this device last saw them is left to
    /// the device that made it, which has saved since, maybe with a newer
    /// mark than the one that synced in here.
    private func childrenToCompare(
        _ job: ParentLockerJob, matches: [UUID: ParentLockerPlanner.Match], rosters: [ParentLockerRoster]
    ) -> Set<UUID>? {
        guard isToday(job.day) else { return job.children }
        rollOwedDay(to: job.day)
        let seen = ParentLockerPlanner.seen(matches: matches, rosters: rosters)
        lastSeen.merge(seen) { $1 }
        guard var only = job.children, !job.imported.isEmpty else { return job.children }
        let elsewhere = ParentLockerPlanner.changedElsewhere(job.imported, before: job.importedBaseline, now: seen)
        if !elsewhere.isEmpty {
            Self.logger.info("ParentLocker: \(elsewhere.count, privacy: .public) synced-in changes left to others")
        }
        only.subtract(elsewhere)
        return only
    }

    /// What ParentLocker holds after a save: what was sent, except where
    /// someone else's mark stood (the Notes box as it was).
    private func noteSaved(_ batch: ParentLockerPlanner.Batch, reply: ParentLockerSaveReply) {
        let courseID = batch.course.courseID
        for entry in batch.entries {
            var row = ParentLockerSeen.Row(
                markID: entry.attendance["attendance_code"]?["id"]?.nonEmptyID,
                comment: entry.attendance["comment"]?.stringValue ?? ""
            )
            if let conflict = reply.conflicts.first(where: { $0.studentID == entry.studentID && !$0.alreadyEqual }) {
                let before = lastSeen[entry.childID]?.rows[courseID]?.comment ?? ""
                row = ParentLockerSeen.Row(markID: conflict.currentMarkID, comment: before)
            }
            lastSeen[entry.childID, default: ParentLockerSeen()].rows[courseID] = row
        }
    }

    /// The classes to read: those that take attendance once a day (so a
    /// class's mark is the child's day). Today, one the office doesn't
    /// expect attendance in is left alone too. Returns the rest in words.
    nonisolated static func coursesToLoad(
        _ courses: [ParentLockerCourse], isToday: Bool
    ) -> (load: [ParentLockerCourse], leftAlone: [String]) {
        var load: [ParentLockerCourse] = []
        var leftAlone: [String] = []
        for course in courses {
            if !course.isDailyAttendance || !course.hasAttendance {
                leftAlone.append("Skipped \(course.name): it doesn't take daily attendance.")
            } else if isToday, course.reportStatus == "not_expected" {
                leftAlone.append("Skipped \(course.name): no attendance is expected today.")
            } else {
                load.append(course)
            }
        }
        return (load, leftAlone)
    }

    private static func conflictLine(
        _ conflict: ParentLockerSaveReply.Conflict, batch: ParentLockerPlanner.Batch,
        rosters: [ParentLockerRoster], day: ParentLockerDay
    ) -> String {
        let childID = batch.entries.first { $0.studentID == conflict.studentID }?.childID
        let marks = rosters.first { $0.course == batch.course }?.marks ?? []
        let current = marks.first { $0.id == conflict.currentMarkID }?.name
        return ParentLockerStatus.conflictLine(name: childID.map(day.name(of:)) ?? "a child", currentMark: current)
    }

    // MARK: - After a run

    private func finish(
        _ job: ParentLockerJob, day: ParentLockerDay, result: ParentLockerRunResult,
        started: Date, previous: ParentLockerStatus
    ) -> ParentLockerReport {
        let report = makeReport(job, day: day, result: result)
        if job.isWholeClass { lastReport = report }
        // An asked-for preview changes nothing here, the status included.
        if job.preview {
            status = previous
            return report
        }
        let matchedAny = result.matches.values.contains { if case .matched = $0 { true } else { false } }
        if !result.wasPreview {
            // A backstop records only while nobody else has (one may have synced in meanwhile).
            let recordedMeanwhile = (job.reason == .backstop || job.reason == .deadline)
                && store.day(job.day, withChildren: false).sentToParentLocker
            if job.isWholeClass, matchedAny, !recordedMeanwhile {
                _ = store.recordSend(on: job.day)
            }
            if day.role == .leadGuide, !result.plan.newMatches.isEmpty {
                _ = store.writeMatches(result.plan.newMatches.mapValues { Optional($0) })
            }
        }
        settleOwed(after: job, startedAt: started)
        var problems = report.problems
        if job.isWholeClass, !matchedAny {
            problems.insert(
                "None of the class's children were found in ParentLocker. " +
                    "Check that you signed in with your school account.", at: 0
            )
        }
        status = ParentLockerStatus(
            state: result.wasPreview ? .previewed : (matchedAny || !job.isWholeClass ? .upToDate : .idle),
            problems: problems, lastSyncAt: clock.now
        )
        return report
    }

    /// What a run that reached ParentLocker settles: the changes made before
    /// it started (one made since goes on its own), a whole-class send owed,
    /// and a retry it covers.
    private func settleOwed(after job: ParentLockerJob, startedAt started: Date) {
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

    /// A run that didn't get through: retry what can be, owe the rest, and
    /// say so plainly.
    private func failed(_ job: ParentLockerJob, error: Error, failure: ParentLockerStatus) {
        Self.logger.error("ParentLocker: a send didn't go (\(String(describing: error), privacy: .public))")
        status = failure
        switch failure.state {
        case .retrying:
            guard job.attempt < Self.retryWaits.count else {
                owe(job)
                status.state = .gaveUp
                return
            }
            var again = job
            again.attempt += 1
            retry = (again, clock.now.addingTimeInterval(Self.retryWaits[job.attempt]))
        case .signedOut:
            signedOutHere()
        case .passwordRefused:
            owe(job)
            try? dependencies.secrets.deleteCookies(site: site)
        default:
            owe(job)
        }
    }

    /// Keeps a failed run's work for the next change, the return to the app
    /// or Send Now. This device's own changes stay owed anyway (they're
    /// cleared only on success); an imported one is left to its own device.
    private func owe(_ job: ParentLockerJob) {
        guard job.isWholeClass, isToday(job.day), job.reason != .request || !job.preview else { return }
        if wholeClass == nil { wholeClass = ParentLockerWholeClass(reason: .owed, due: nil) }
        saveOwed()
    }

    // MARK: - Report

    private func makeReport(
        _ job: ParentLockerJob, day: ParentLockerDay, result: ParentLockerRunResult
    ) -> ParentLockerReport {
        var childByStudent: [String: UUID] = [:]
        for (childID, match) in result.matches {
            if case .matched(let studentID, _) = match { childByStudent[studentID] = childID }
        }
        let classes = result.rosters.compactMap { roster -> ParentLockerReport.ClassReport? in
            let ours = roster.students.compactMap { childByStudent[$0.studentID] }
            guard !ours.isEmpty else { return nil }
            let batch = result.plan.batches.first { $0.course == roster.course }
            let changes = (batch?.entries ?? []).map { entry in
                ParentLockerReport.Change(
                    name: day.name(of: entry.childID),
                    mark: ParentLockerMark.find(entry.type, in: roster.marks)?.name ?? entry.type.rawValue.capitalized,
                    note: entry.comment.flatMap { $0.isEmpty ? nil : $0 }
                )
            }
            let alreadyIn = ours.filter { result.plan.upToDate.contains($0) }.map(day.name(of:))
            return ParentLockerReport.ClassReport(name: roster.course.name, changes: changes, alreadyIn: alreadyIn)
        }
        let problems = ParentLockerStatus.problems(
            for: result.plan.skipped, names: day.name(of:), isGuide: day.role == .leadGuide
        ) + result.conflicts
        return ParentLockerReport(
            day: job.day, wasPreview: result.wasPreview, classes: classes, problems: problems,
            classesLeftAlone: result.leftAlone, savedCount: result.savedCount
        )
    }
}
