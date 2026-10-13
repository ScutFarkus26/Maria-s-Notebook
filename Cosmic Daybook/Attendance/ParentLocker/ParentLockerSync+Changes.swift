import Foundation
import CoreData

// What starts a live update: a save of the day's attendance (this device's
// or one synced in), the first import after launch or a return (or 20 s
// without one), and the guide's backstops. Nothing is noted before "after".

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
        guard state.isAfter else { return reschedule() }
        rollOwedDay(to: day)
        let now = clock.now
        if imported {
            // What this device last saw of each, kept from before the change
            // arrived: ParentLocker holding anything else by the time it goes
            // means its own device has saved it since.
            let fresh = children.subtracting(localChanges.keys)
            for child in fresh.subtracting(importedChildren) { importedBaseline[child] = lastSeen[child] }
            importedChildren.formUnion(fresh)
            if importedDue == nil, !importedChildren.isEmpty { importedDue = now.addingTimeInterval(Self.importedWait) }
        } else {
            for child in children {
                localChanges[child] = now
                importedBaseline[child] = nil
            }
            importedChildren.subtract(children)
            localDue = now.addingTimeInterval(Self.localQuiet)
            // A whole-class send owed after a failure goes with the next change.
            if wholeClass != nil, wholeClass?.due == nil { wholeClass?.due = localDue }
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
        if wholeClass != nil, wholeClass?.due == nil { wholeClass?.due = now }
        let state = store.day(now, withChildren: false)
        if state.method == .parentLocker, state.isSchoolDay {
            considerBackstop(state, on: now)
            considerDeadline(state, on: now)
        }
        reschedule()
    }
}
