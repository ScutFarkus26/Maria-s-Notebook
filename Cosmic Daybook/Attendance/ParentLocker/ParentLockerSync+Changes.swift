import Foundation
import CoreData

// What starts a live update: a save of the day's attendance (this device's
// or one synced in), the first import after launch or a return, and the
// guide's backstop. Nothing is noted before "after".

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
        guard state.isAfter else { return }
        rollOwedDay(to: day)
        let now = clock.now
        if imported {
            importedChildren.formUnion(children.subtracting(localChanges.keys))
            if importedDue == nil, !importedChildren.isEmpty { importedDue = now.addingTimeInterval(Self.importedWait) }
        } else {
            for child in children { localChanges[child] = now }
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
        wholeClass = ParentLockerWholeClass(reason: .backstop, due: clock.now.addingTimeInterval(Self.backstopWait))
    }

    /// A CloudKit import finished: the catch-up waiting on it goes.
    func importFinished() {
        guard awaitingImport else { return }
        awaitingImport = false
        releaseCatchUp()
    }

    /// Back to the app (or the Mac app made active): the sign-in is read
    /// again, and what's owed waits for the first import, then goes.
    func appReturned() {
        refreshSignIn()
        // Changes still owed from before (a failed send) wait for the import
        // with the rest; one made seconds ago keeps its own short wait.
        if localDue == nil {
            catchUpChildren.formUnion(localChanges.keys)
            localChanges = [:]
        }
        awaitingImport = dependencies.importsExpected
        if !awaitingImport { releaseCatchUp() }
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
        if state.method == .parentLocker, state.isSchoolDay { considerBackstop(state, on: now) }
        reschedule()
    }
}
