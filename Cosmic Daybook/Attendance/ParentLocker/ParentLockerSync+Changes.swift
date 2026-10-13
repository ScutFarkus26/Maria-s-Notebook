import Foundation
import CoreData
import OSLog

// What starts a live update: a save of the day's attendance (this device's
// or one synced in), the first import after launch or a return (or 20 s
// without one), and the guide's backstops. A change made before "after" is
// kept until the day is. And what this device last saw in ParentLocker,
// which a change synced in (or a backstop) goes over only while ParentLocker
// still holds it, and the line while nothing is under way.

extension ParentLockerSync {

    // MARK: - Changes

    /// Attendance records saved: by this device (`imported` false), or synced
    /// in. Only today's count; the rest go by Send Now or MCP.
    func recordsSaved(_ records: [NSManagedObjectID], imported: Bool) {
        guard isSignedIn else { return }
        let day = today
        noteChanges(store.children(inRecords: records, on: day), imported: imported, on: day)
    }

    /// Children whose marks on `day` changed. Before "after" they're kept,
    /// unscheduled, and go once the day is (`releaseEarlyChanges`); this
    /// device's own are kept with what's owed, across launches too.
    func noteChanges(_ children: Set<UUID>, imported: Bool, on day: Date) {
        guard !children.isEmpty, isSignedIn, isToday(day) else { return }
        let state = store.day(day, withChildren: false)
        guard state.method == .parentLocker, state.isSchoolDay else { return }
        // A new day's first change rolls first, so it never clears the
        // backstop it schedules (bug hunt 2026-10-13 afternoon, H3).
        rollOwedDay(to: day, changing: children)
        rememberMarksBefore(children, on: day)
        considerBackstop(state, on: day)
        considerDeadline(state, on: day)
        guard isAfter(state, on: day) else {
            noteEarly(children, imported: imported, on: day)
            refreshStatus(state)
            return reschedule()
        }
        releaseEarlyChanges(on: day, sent: state.sentToParentLocker)
        let now = clock.now
        if imported {
            // What this device last saw of each, kept from before the change
            // arrived: ParentLocker holding anything else by the time it goes
            // means its own device has saved it since. Nothing seen of a child
            // yet today (just after a launch): what ParentLocker holds now.
            // A child with a change of this device's own still to go is its.
            let fresh = children.subtracting(localChanges.keys).subtracting(earlyLocal)
            let arrived = fresh.subtracting(importedChildren)
            for child in arrived { importedBaseline[child] = lastSeen[child] }
            importedChildren.formUnion(fresh)
            loadBaseline(for: arrived.filter { lastSeen[$0] == nil && !baselineRead.contains($0) }, on: day)
            if importedDue == nil, !importedChildren.isEmpty { importedDue = now.addingTimeInterval(Self.importedWait) }
        } else {
            for child in children { localChanges[child] = now }
            forgetImported(children)
            forgetEarlyLocal(children)
            localDue = now.addingTimeInterval(Self.localQuiet)
            // A whole-class send owed after a failure goes with the next change.
            releaseWholeClass(at: now.addingTimeInterval(Self.localQuiet))
            saveOwed()
        }
        reschedule()
    }

    /// Changes made before "after", kept until it: this device's own (saved
    /// with what's owed) and those synced in, each the newer word on its
    /// child, as after "after".
    private func noteEarly(_ children: Set<UUID>, imported: Bool, on day: Date) {
        if imported {
            earlyChanges.formUnion(children.subtracting(earlyLocal))
        } else {
            keepEarlyLocal(children, marks: store.marks(of: children, on: day))
            earlyChanges.subtract(children)
            saveOwed()
        }
    }

    /// This device's own `children`, changed before "after", owed while
    /// their mark here (`marks`) has something to send. One left unmarked
    /// (an Undo's) has nothing, and ParentLocker can't clear a mark anyway.
    func keepEarlyLocal(_ children: Set<UUID>, marks: [UUID: ParentLockerPlanner.DayMark]) {
        let nothing = children.filter { ParentLockerPlanner.wanted(for: marks[$0]) == .nothing }
        earlyLocal.formUnion(children.subtracting(nothing))
        forgetEarlyLocal(nothing)
    }

    /// Changes made before "after" go now the day is "after" here (review of
    /// the afternoon fixes, H4):
    /// - **This device's own** go as its own changes, over whatever
    ///   ParentLocker holds: the guide's mark made at 8:44:50 is newer than
    ///   the absence a phone that hadn't seen it sends at 8:45. With the
    ///   day's send not yet recorded (another device's Close Arrival seen
    ///   here), they wait a minute, so that send lands first; once it is,
    ///   seconds. Taken over what this device last saw, as before, one was
    ///   judged changed by someone else and never went.
    /// - **Those synced in** go as changes synced in do: over what this
    ///   device last saw of each in ParentLocker, read now when it has seen
    ///   nothing, so a mark another device saved since is left to it.
    func releaseEarlyChanges(on day: Date, sent: Bool) {
        if !earlyLocal.isEmpty, earlyLocalDue == nil {
            earlyLocalDue = clock.now.addingTimeInterval(sent ? Self.localQuiet : Self.importedWait)
        }
        let early = earlyChanges.subtracting(localChanges.keys).subtracting(earlyLocal).subtracting(importedChildren)
        earlyChanges = []
        guard !early.isEmpty else { return }
        for child in early { importedBaseline[child] = lastSeen[child] }
        importedChildren.formUnion(early)
        loadBaseline(for: early.filter { lastSeen[$0] == nil && !baselineRead.contains($0) }, on: day)
        if importedDue == nil { importedDue = clock.now.addingTimeInterval(Self.importedWait) }
    }

    /// This device's own early changes `children`, now covered: by a newer
    /// change of its own, or a whole-class send.
    func forgetEarlyLocal(_ children: Set<UUID>) {
        earlyLocal.subtract(children)
        if earlyLocal.isEmpty { earlyLocalDue = nil }
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

    // MARK: - Imports, returns and a new day

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
    /// the first import, then goes. A retry that came due while away waits
    /// too: going first, it would send this device's view from before the
    /// trip over marks made since (bug hunt 2026-10-13 afternoon, H5).
    func appReturned() {
        refreshSignIn()
        if let pending = retry {
            retry = nil
            holdForCatchUp(pending.job)
        }
        // Changes still owed from before (a failed send) wait for the import
        // with the rest; one made seconds ago keeps its own short wait.
        if localDue == nil {
            catchUpChildren.formUnion(localChanges.keys)
            localChanges = [:]
        }
        waitForImport()
        refreshStatus()
    }

    /// A retry held back on the way back: a whole class becomes a send owed,
    /// released by the catch-up as a retry; the children synced in wait again
    /// with what this device had seen of them (its own changes are owed anyway).
    private func holdForCatchUp(_ job: ParentLockerJob) {
        guard isToday(job.day) else { return }
        if job.isWholeClass {
            if wholeClass == nil { wholeClass = ParentLockerWholeClass(retrying: job) }
            return saveOwed()
        }
        for child in job.imported where importedChildren.insert(child).inserted {
            importedBaseline[child] = job.importedBaseline[child]
            importedBefore[child] = job.importedBefore[child]
        }
        if !importedChildren.isEmpty, importedDue == nil {
            importedDue = clock.now.addingTimeInterval(Self.importedWait)
        }
    }

    /// Midnight (`.NSCalendarDayChanged`): yesterday's work goes, and the line
    /// moves on to the new day, which the Mac, open all night, otherwise
    /// never did (bug hunt 2026-10-13 afternoon, H3).
    func dayChanged() {
        rollOwedDay(to: clock.now)
        saveOwed()
        let state = store.day(today, withChildren: true)
        if isSignedIn { rememberMarks(state) }
        refreshStatus(state)
        reschedule()
    }

    /// The owed changes go now (after the import, or a sign-in), and a
    /// guide's device that finds arrival closed with nothing sent backs up.
    /// Changes owed from before "after" that it hasn't reached yet wait for
    /// it again (review of the afternoon fixes, H4).
    func releaseCatchUp() {
        guard isSignedIn else { return }
        let now = clock.now
        rollOwedDay(to: now)
        let state = store.day(now, withChildren: false)
        let follows = state.method == .parentLocker && state.isSchoolDay
        if !catchUpChildren.isEmpty {
            if follows, !isAfter(state, on: now) {
                earlyLocal.formUnion(catchUpChildren)
            } else {
                for child in catchUpChildren where localChanges[child] == nil { localChanges[child] = now }
                localDue = now
            }
            catchUpChildren = []
        }
        releaseWholeClass(at: now)
        if follows {
            considerBackstop(state, on: now)
            considerDeadline(state, on: now)
            if isAfter(state, on: now) { releaseEarlyChanges(on: now, sent: state.sentToParentLocker) }
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

    // MARK: - The marks before a change

    /// Today's marks as this device has just read them in full.
    func rememberMarks(_ day: ParentLockerDay) {
        knownMarks = day.marks
        knownMarksDay = today
    }

    /// Keeps the mark each of `children` had here before its first change
    /// not yet sent, for a change synced in (or made before "after") that
    /// this device has no ParentLocker row to measure by (bug hunt 2026-10-13
    /// afternoon, M5), then brings today's marks up to date. Nothing is kept
    /// when this device hasn't read today's marks. This device's own changes
    /// after "after" go without it (`forgetImported`).
    private func rememberMarksBefore(_ children: Set<UUID>, on day: Date) {
        guard var known = knownMarks else { return }
        let current = store.marks(of: children, on: day)
        for child in children {
            if importedBefore[child] == nil, lastSeen[child] == nil { importedBefore[child] = .some(known[child]) }
            known[child] = current[child]
        }
        knownMarks = known
    }
}
