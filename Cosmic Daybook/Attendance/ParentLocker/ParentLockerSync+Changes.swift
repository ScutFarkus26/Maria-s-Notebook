import Foundation
import CoreData
import OSLog

// What starts a live update: a save of the day's attendance (this device's
// or one synced in), the first import after launch or a return (or 20 s
// without one), and the guide's backstops. Nothing is noted before "after".
// And what this device last saw in ParentLocker, which a change synced in
// (or a backstop) goes over only while ParentLocker still holds it, and the
// line while nothing is under way.

extension ParentLockerSync {

    // MARK: - Changes

    /// Attendance records saved: by this device (`imported` false), or synced
    /// in. Only today's count; the rest go by Send Now or MCP.
    func recordsSaved(_ records: [NSManagedObjectID], imported: Bool) {
        guard isSignedIn else { return }
        let day = today
        noteChanges(store.children(inRecords: records, on: day), imported: imported, on: day)
    }

    /// Children whose marks on `day` changed. Nothing is noted before "after":
    /// the whole-class send covers those.
    func noteChanges(_ children: Set<UUID>, imported: Bool, on day: Date) {
        guard !children.isEmpty, isSignedIn, isToday(day) else { return }
        let state = store.day(day, withChildren: false)
        guard state.method == .parentLocker, state.isSchoolDay else { return }
        considerBackstop(state, on: day)
        considerDeadline(state, on: day)
        guard isAfter(state, on: day) else { return reschedule() }
        rollOwedDay(to: day)
        let now = clock.now
        if imported {
            // What this device last saw of each, kept from before the change
            // arrived: ParentLocker holding anything else by the time it goes
            // means its own device has saved it since. Nothing seen of a child
            // yet today (just after a launch): what ParentLocker holds now.
            let fresh = children.subtracting(localChanges.keys)
            let arrived = fresh.subtracting(importedChildren)
            for child in arrived { importedBaseline[child] = lastSeen[child] }
            importedChildren.formUnion(fresh)
            loadBaseline(for: arrived.filter { lastSeen[$0] == nil && !baselineRead.contains($0) }, on: day)
            if importedDue == nil, !importedChildren.isEmpty { importedDue = now.addingTimeInterval(Self.importedWait) }
        } else {
            for child in children {
                localChanges[child] = now
                importedBaseline[child] = nil
            }
            importedChildren.subtract(children)
            localDue = now.addingTimeInterval(Self.localQuiet)
            // A whole-class send owed after a failure goes with the next change.
            releaseWholeClass(at: now.addingTimeInterval(Self.localQuiet))
            saveOwed()
        }
        reschedule()
    }

    /// The guide's backstop: arrival closed somewhere and no ParentLocker send
    /// recorded, so one of the guide's signed-in devices sends in 60 s.
    func considerBackstop(_ state: ParentLockerDay, on day: Date) {
        guard state.role == .leadGuide, state.method == .parentLocker, state.arrivalClosed,
              !state.sentToParentLocker, isSignedIn, isToday(day), wholeClass == nil,
              backstopDay.map({ !isSameDay($0, day) }) ?? true else { return }
        backstopDay = day
        deadlineDue = nil
        wholeClass = ParentLockerWholeClass(reason: .backstop, due: clock.now.addingTimeInterval(Self.backstopWait))
    }

    /// The guide's backstop at the day's due time: Close Arrival with nobody
    /// left to mark writes no automatic absence, so a phone that closed it
    /// without being signed in leaves nothing that says arrival closed. A
    /// minute after the due time (or after now, when that's later) one of the
    /// guide's signed-in devices checks, and sends the whole class if
    /// everyone is marked and still nothing is recorded (`.deadline`).
    func considerDeadline(_ state: ParentLockerDay, on day: Date) {
        guard deadlineDue == nil, state.role == .leadGuide, state.method == .parentLocker, state.isSchoolDay,
              !state.sentToParentLocker, isSignedIn, isToday(day), wholeClass == nil,
              backstopDay.map({ !isSameDay($0, day) }) ?? true,
              let deadline = state.deadline(on: day, calendar: dependencies.calendar) else { return }
        deadlineDue = max(deadline, clock.now).addingTimeInterval(Self.backstopWait)
    }

    /// The catch-up waits for the first CloudKit import, but no longer than
    /// `importWaitLimit`: with nothing new in CloudKit, none may come. Signed
    /// out, there's nothing to catch up (signing in releases it).
    func waitForImport() {
        awaitingImport = dependencies.importsExpected && isSignedIn
        importWaitEnds = awaitingImport ? clock.now.addingTimeInterval(Self.importWaitLimit) : nil
        if awaitingImport { reschedule() } else { releaseCatchUp() }
    }

    /// A CloudKit import finished, or the wait for one ran out: the catch-up
    /// waiting on it goes.
    func importFinished() {
        guard awaitingImport else { return }
        awaitingImport = false
        importWaitEnds = nil
        releaseCatchUp()
    }

    /// The Mac app went to the background.
    func appResigned() {
        resignedAt = clock.now
    }

    /// The app became active. On the Mac that happens at every switch
    /// between apps, so only a return after `returnAbsence` away counts there.
    func appBecameActive() {
        defer { resignedAt = nil }
        if dependencies.returnNeedsAbsence {
            guard let resignedAt, clock.now.timeIntervalSince(resignedAt) >= Self.returnAbsence else { return }
        }
        appReturned()
    }

    /// Back to the app: the sign-in is read again, and what's owed waits for
    /// the first import, then goes.
    func appReturned() {
        refreshSignIn()
        // Changes still owed from before (a failed send) wait for the import
        // with the rest; one made seconds ago keeps its own short wait.
        if localDue == nil {
            catchUpChildren.formUnion(localChanges.keys)
            localChanges = [:]
        }
        waitForImport()
        refreshStatus()
    }

    /// Brings the line up to date with the day while nothing is under way:
    /// off, signed out, waiting for arrival, or as the last run left it (a
    /// run from another day says nothing about this one).
    func refreshStatus() {
        let state = store.day(today, withChildren: false)
        guard state.method == .parentLocker else { return status = ParentLockerStatus(state: .off) }
        guard isSignedIn else { return status = ParentLockerStatus(state: .signedOut) }
        guard !savedPasswordRefused else {
            if status.state != .passwordRefused { status = ParentLockerStatus(state: .passwordRefused) }
            return
        }
        let quiet: ParentLockerStatus.State = isAfter(state, on: today) || !state.isSchoolDay
            ? .idle : .waitingForArrival
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

    /// The owed changes go now (after the import, or a sign-in), and a
    /// guide's device that finds arrival closed with nothing sent backs up.
    func releaseCatchUp() {
        guard isSignedIn else { return }
        let now = clock.now
        rollOwedDay(to: now)
        if !catchUpChildren.isEmpty {
            for child in catchUpChildren where localChanges[child] == nil { localChanges[child] = now }
            catchUpChildren = []
            localDue = now
        }
        releaseWholeClass(at: now)
        let state = store.day(now, withChildren: false)
        if state.method == .parentLocker, state.isSchoolDay {
            considerBackstop(state, on: now)
            considerDeadline(state, on: now)
        }
        reschedule()
    }

    // MARK: - "After"

    /// Whether `state`, the day `date`, is past "after" here: arrival closed
    /// or the day sent, as the records say, or Close Arrival & Send made here
    /// (or a whole-class send started), which a child marked Late in the Undo
    /// window, taking the last automatic absence with them, doesn't undo.
    func isAfter(_ state: ParentLockerDay, on date: Date) -> Bool {
        state.isAfter || (arrivalClosedHere && owedDay.map { isSameDay($0, date) } == true)
    }

    /// A whole-class send started here: today is "after" on this device from
    /// now on, across launches too.
    func markArrivalClosed() {
        rollOwedDay(to: clock.now)
        guard !arrivalClosedHere else { return }
        arrivalClosedHere = true
        saveOwed()
    }

    /// A whole-class send waiting (for a sign-in, or owed) goes at `moment`,
    /// but never before Close Arrival's Undo has passed: it could still be undone.
    func releaseWholeClass(at moment: Date) {
        guard wholeClass != nil, wholeClass?.due == nil else { return }
        wholeClass?.due = max(moment, undoEndsAt ?? moment)
    }

    // MARK: - What this device last saw

    /// The children `job` compares, once today's rosters are in (which also
    /// become what this device last saw), and those it leaves to others. A
    /// child ParentLocker no longer holds as this device last saw them was
    /// saved since by another device, maybe with a newer mark than has synced
    /// in here, and is left to it: an imported change's child, and any child
    /// of the guide's backstops, which send the whole class from a device
    /// that may not have caught up with the one that closed arrival.
    func childrenToCompare(
        _ job: ParentLockerJob, matches: [UUID: ParentLockerPlanner.Match], rosters: [ParentLockerRoster]
    ) -> (only: Set<UUID>?, leftToOthers: Set<UUID>) {
        guard isToday(job.day) else { return (job.children, []) }
        rollOwedDay(to: job.day)
        let seen = ParentLockerPlanner.seen(matches: matches, rosters: rosters)
        let before = lastSeen
        lastSeen.merge(seen) { $1 }
        let compared: Set<UUID>
        let baseline: [UUID: ParentLockerSeen]
        if job.reason == .backstop || job.reason == .deadline {
            (compared, baseline) = (Set(matches.keys), before)
        } else if job.children != nil, !job.imported.isEmpty {
            (compared, baseline) = (job.imported, job.importedBaseline)
        } else {
            return (job.children, [])
        }
        let elsewhere = ParentLockerPlanner.changedElsewhere(compared, before: baseline, now: seen)
        guard !elsewhere.isEmpty else { return (job.children, []) }
        Self.logger.info("ParentLocker: \(elsewhere.count, privacy: .public) children left to others")
        return ((job.children ?? Set(matches.keys)).subtracting(elsewhere), elsewhere)
    }

    /// What ParentLocker holds after a save: what was sent, except where
    /// someone else's mark stood (the Notes box as it was).
    func noteSaved(_ batch: ParentLockerPlanner.Batch, reply: ParentLockerSaveReply) {
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

    /// Changes synced in for children this device hasn't seen in ParentLocker
    /// today (just after a launch): the class lists are read now, read only,
    /// so each change is measured against what ParentLocker holds as it
    /// arrives. Without that, any mark there (the morning's send) would read
    /// as another device's newer one, and the change would never go. Each
    /// child is read for at most once a day (`baselineRead`).
    func loadBaseline(for children: Set<UUID>, on day: Date) {
        let waiting = children.subtracting(baselineWaiting)
        guard !waiting.isEmpty, !isStopped else { return }
        baselineWaiting.formUnion(waiting)
        let previous = baselineTask
        baselineTask = Task { [weak self] in
            await previous?.value
            await self?.fillBaseline(for: waiting, on: day)
        }
    }

    /// Reads the class lists and fills what this device saw, never over what
    /// a save since has set, then the baselines still waiting for it. Never
    /// alongside a run: with no saved cookies both would sign in, and a wrong
    /// password would be tried twice before its refusal was remembered. A run
    /// that read the lists meanwhile leaves nothing to read.
    private func fillBaseline(for children: Set<UUID>, on day: Date) async {
        defer { baselineWaiting.subtract(children) }
        await waitForActiveRun()
        guard !Task.isCancelled, !isStopped, let owedDay, isSameDay(owedDay, day) else { return }
        if children.contains(where: { lastSeen[$0] == nil }) {
            readingBaseline = true
            defer { readingBaseline = false }
            let rosters: [ParentLockerRoster]
            do {
                rosters = try await loadRosters(day: day)
            } catch {
                Self.logger.info("ParentLocker: couldn't read the class lists for changes synced in")
                return
            }
            guard let stillOwed = self.owedDay, isSameDay(stillOwed, day) else { return }
            baselineRead.formUnion(children)
            let state = store.day(day, withChildren: true)
            let matches = ParentLockerPlanner.match(children: state.children, rosters: rosters)
            let seen = ParentLockerPlanner.seen(matches: matches, rosters: rosters)
            for (child, rows) in seen where lastSeen[child] == nil { lastSeen[child] = rows }
        }
        for child in children where importedChildren.contains(child) && importedBaseline[child] == nil {
            importedBaseline[child] = lastSeen[child]
        }
    }
}
