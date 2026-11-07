import Foundation
import OSLog

// What this device last saw in ParentLocker: a change synced in (or made
// before "after"), the guide's backstops and a whole-class retry go over a
// child only while ParentLocker still holds them as this device saw them;
// anything else there was saved since by another device, maybe with a newer
// mark, and is left to it, unless it's what this device's own save sent.
// What's owed, kept across launches with what its saves sent and the notes
// it wrote. And reading the class lists, one class at a time.

extension ParentLockerSync {

    // MARK: - What this device last saw

    /// The children `job` compares, once today's rosters are in (which also
    /// become what this device last saw), and those it leaves to others. A
    /// child ParentLocker no longer holds as this device last saw them was
    /// saved since by another device, maybe with a newer mark than has synced
    /// in here, and is left to it: an imported change's child, and any child
    /// of the guide's backstops and of a whole-class retry or send owed,
    /// which go from a device that may not have caught up with the others.
    func childrenToCompare(
        _ job: ParentLockerJob, matches: [UUID: ParentLockerPlanner.Match], rosters: [ParentLockerRoster]
    ) -> (only: Set<UUID>?, leftToOthers: Set<UUID>) {
        guard isToday(job.day) else { return (job.children, []) }
        rollOwedDay(to: job.day)
        let seen = ParentLockerPlanner.seen(matches: matches, rosters: rosters)
        let before = lastSeen
        lastSeen.merge(seen) { $1 }
        // What this device's saves sent is now read: there, or not.
        let sent = sending
        for (child, rows) in seen {
            for course in rows.rows.keys { sending[child]?[course] = nil }
            if sending[child]?.isEmpty == true { sending[child] = nil }
        }
        let compared: Set<UUID>
        let baseline: [UUID: ParentLockerSeen]
        if job.comparesWithLastSeen {
            (compared, baseline) = (Set(matches.keys), before)
        } else if job.children != nil, !job.imported.isEmpty {
            (compared, baseline) = (job.imported, Self.measuredBaseline(of: job, seen: seen, rosters: rosters))
        } else {
            return (job.children, [])
        }
        let elsewhere = ParentLockerPlanner.changedElsewhere(compared, before: baseline, now: seen)
            .filter { !Self.savedHere(sent[$0], before: baseline[$0], now: seen[$0]) }
        guard !elsewhere.isEmpty else { return (job.children, []) }
        Self.logger.info("ParentLocker: \(elsewhere.count, privacy: .public) children left to others")
        return ((job.children ?? Set(matches.keys)).subtracting(elsewhere), elsewhere)
    }

    /// What each child synced in is measured by: what this device had seen of
    /// them as the change arrived; or, with nothing seen (the class lists
    /// couldn't be read then), ParentLocker as it is now, when it still holds
    /// what the child's mark here before the change sends, so nobody has
    /// saved them since (bug hunt 2026-10-13 afternoon, M5). Before, such a
    /// change was dropped whenever ParentLocker held any mark.
    private static func measuredBaseline(
        of job: ParentLockerJob, seen: [UUID: ParentLockerSeen], rosters: [ParentLockerRoster]
    ) -> [UUID: ParentLockerSeen] {
        var baseline = job.importedBaseline
        for (child, earlier) in job.importedBefore where baseline[child] == nil {
            if ParentLockerPlanner.holdsEarlierMark(earlier, now: seen[child], rosters: rosters) {
                baseline[child] = seen[child]
            }
        }
        return baseline
    }

    /// Whether a child ParentLocker holds otherwise than this device last saw
    /// them holds only what this device's own save sent (`noted`), whose
    /// reply was lost, or what it saw: no other device has saved them, so
    /// they're this device's own, up to date (bug hunt 2026-11-05 #3). What
    /// it would send alone doesn't count: a backstop that finds the class
    /// saved by someone else still leaves it, and its record, to them.
    static func savedHere(
        _ noted: [Int: ParentLockerSentRow]?, before: ParentLockerSeen?, now: ParentLockerSeen?
    ) -> Bool {
        guard let noted, !noted.isEmpty, let now else { return false }
        return now.rows.allSatisfy { course, row in
            if noted[course]?.landed(in: row) == true { return true }
            guard let earlier = before?.rows[course] else { return row.markID == nil }
            return earlier == row
        }
    }

    /// The rows a save of today's is about to send, kept until the class is
    /// read again (`childrenToCompare`), and the notes it writes, kept for
    /// the day: both with what's owed, before the save goes, so a relaunch
    /// knows them for this device's own (review of the 2026-11-05 fixes, E5,
    /// W3). A class of a whole-class send about to go means Close Arrival's
    /// Undo can no longer take all of it back (#14).
    func noteSending(_ batch: ParentLockerPlanner.Batch, wholeClass: Bool) {
        let courseID = batch.course.courseID
        for entry in batch.entries {
            sending[entry.childID, default: [:]][courseID] = ParentLockerSentRow(entry)
            if let note = entry.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
                ownNotes[entry.childID, default: [:]][courseID, default: []].insert(note)
            }
        }
        // Noted before it's saved with what's owed, so a relaunch knows it (#4).
        let firstClass = wholeClass && !closeArrivalBatchSent
        if firstClass { closeArrivalBatchSent = true }
        saveOwed()
        guard firstClass else { return }
        refreshCloseArrivalUnsent()
    }

    /// What ParentLocker holds after a save: what was sent, except where
    /// someone else's mark stood (the Notes box as it was). The rows sent
    /// stay noted until the class is read again: what this device last saw
    /// isn't kept across launches, so only they tell a relaunch the save was
    /// its own (E5).
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
    /// child is read for at most once a day (`baselineRead`). A change whose
    /// read is still going when its 60 s are up waits for it
    /// (`readyImported`), and goes once it's in.
    func loadBaseline(for children: Set<UUID>, on day: Date) {
        let waiting = children.subtracting(baselineWaiting)
        guard !waiting.isEmpty, !isStopped else { return }
        baselineWaiting.formUnion(waiting)
        let previous = baselineTask
        baselineTask = Task { [weak self] in
            await previous?.value
            await self?.fillBaseline(for: waiting, on: day)
            self?.reschedule()
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
            let read: (rosters: [ParentLockerRoster], unread: [ParentLockerCourse])
            do {
                read = try await loadRosters(day: day)
            } catch {
                Self.logger.info("ParentLocker: couldn't read the class lists for changes synced in")
                return
            }
            guard let stillOwed = self.owedDay, isSameDay(stillOwed, day) else { return }
            let state = store.day(day, withChildren: true)
            let matches = ParentLockerPlanner.match(children: state.children, rosters: read.rosters)
            let seen = ParentLockerPlanner.seen(matches: matches, rosters: read.rosters)
            // A class that wouldn't load is read again at its children's next change (#5).
            baselineRead.formUnion(read.unread.isEmpty ? children : children.filter { seen[$0] != nil })
            for (child, rows) in seen where lastSeen[child] == nil { lastSeen[child] = rows }
        }
        for child in children where importedChildren.contains(child) && importedBaseline[child] == nil {
            importedBaseline[child] = lastSeen[child]
        }
    }

    // MARK: - Owed, kept across launches

    /// Never from a stopped sync: the sync that took its place owns what's
    /// owed (bug hunt 2026-11-03 #1).
    func saveOwed() {
        guard !isStopped else { return }
        guard let owedDay else { return dependencies.unsent.save(nil) }
        let wholeClass = owedWholeClass
        dependencies.unsent.save(ParentLockerUnsent(
            day: AppCalendar.dayID(owedDay),
            children: Set(localChanges.keys).union(catchUpChildren).union(earlyLocal),
            wholeClass: wholeClass != nil,
            arrivalClosed: arrivalClosedHere,
            reason: wholeClass?.rawValue,
            sent: sending,
            notes: ownNotes,
            batchSent: closeArrivalBatchSent
        ))
    }

    /// What this device still owes from before launch. A whole-class send
    /// goes as a retry, over only what this device sees in ParentLocker by
    /// then (`ParentLockerJob.comparesWithLastSeen`): the others may have
    /// sent the class meanwhile, with newer marks. It comes back as itself: a
    /// Close Arrival & Send, which its Undo still stops, or a Send Now (bug
    /// hunt 2026-11-05 #16); one saved before then with arrival closed here
    /// is a Close Arrival & Send. Either, still waiting for a sign-in, asks
    /// for it again (#15). What today's saves sent and the notes this device
    /// wrote come back too (review of the 2026-11-05 fixes, E5, W3).
    func loadOwed() {
        guard let saved = dependencies.unsent.load() else { return }
        guard saved.day == AppCalendar.dayID(today) else { return dependencies.unsent.save(nil) }
        owedDay = today
        catchUpChildren = saved.children
        arrivalClosedHere = saved.arrivalClosed
        sending = saved.sent
        ownNotes = saved.notes
        // Kept with what's owed: in memory alone it was false after every
        // relaunch, and Siri's Undo of a half-sent Close Arrival said only
        // "Arrival is open again" (bug hunt 2026-11-06, #4).
        closeArrivalBatchSent = saved.batchSent
        defer { refreshCloseArrivalUnsent() }
        guard saved.wholeClass, wholeClass == nil else { return }
        let reason = saved.reason.flatMap(ParentLockerWholeClass.Reason.init(rawValue:))
            ?? (saved.arrivalClosed ? .closeArrival : .owed)
        wholeClass = ParentLockerWholeClass(reason: reason, due: nil, attempt: 1)
        if reason == .closeArrival || reason == .sendNow, needsSignIn,
           store.day(today, withChildren: false).method == .parentLocker {
            awaitsSignIn = true
        }
    }

    // MARK: - Reading the class lists

    /// A class's roster that couldn't be read for now, and why.
    typealias UnreadClass = (course: ParentLockerCourse, error: ParentLockerError)

    /// The rosters of the classes that take daily attendance on `day`, for
    /// Match Names: read only, signing in again if needed. A class that
    /// won't load for now comes back unread, for the screen to name (bug
    /// hunt 2026-11-05 #5).
    func loadRosters(day: Date) async throws -> (rosters: [ParentLockerRoster], unread: [ParentLockerCourse]) {
        let today = isToday(day)
        return try await withTransport(site: site) { transport in
            let courses = Self.coursesToLoad(try await transport.courses(on: today ? nil : day), isToday: today).load
            let read = try await Self.readRosters(courses, day: day, transport: transport)
            return (read.rosters, read.unread.map(\.course))
        }
    }

    /// `courses`' rosters for `day`, one class at a time. A class that won't
    /// load for now (unreachable, or refused) is passed over so the others
    /// still go, and comes back with its error; any other error stops the
    /// read (a sign-out signs in again, a changed page stops the send), and
    /// so does every class failing (bug hunt 2026-11-05 #5).
    static func readRosters(
        _ courses: [ParentLockerCourse], day: Date, transport: any ParentLockerTransport
    ) async throws -> (rosters: [ParentLockerRoster], unread: [UnreadClass]) {
        var rosters: [ParentLockerRoster] = []
        var unread: [UnreadClass] = []
        for course in courses {
            do {
                rosters.append(try await transport.roster(course: course, date: day))
            } catch let error as ParentLockerError where passesOver(error) {
                logger.info("ParentLocker: a class's list wouldn't load; the others go on")
                unread.append((course, error))
            }
        }
        if rosters.isEmpty, let error = classError(unread) { throw error }
        return (rosters, unread)
    }

    /// The errors a class is passed over for: "try again later", and the
    /// site's own refusal of that class.
    private static func passesOver(_ error: ParentLockerError) -> Bool {
        switch error {
        case .unreachable, .refused: true
        default: false
        }
    }

    /// What a run with classes unread ends on, so it's retried (or owed) and
    /// not recorded: "try again later" when any class said so.
    static func classError(_ unread: [UnreadClass]) -> ParentLockerError? {
        unread.contains { $0.error == .unreachable } ? .unreachable : unread.first?.error
    }

    /// Today's classes unread, split: those that leave the run unfinished,
    /// and those ParentLocker refused today before, which stand, so the day
    /// is recorded once every other class has gone and the class isn't sent
    /// again at every change (review of the 2026-11-05 fixes, E7). A first
    /// refusal may pass, and leaves the run unfinished.
    func standingRefusals(_ unread: [UnreadClass]) -> (unfinished: [UnreadClass], refused: [ParentLockerCourse]) {
        var unfinished: [UnreadClass] = []
        var refused: [ParentLockerCourse] = []
        for item in unread {
            guard case .refused = item.error else {
                unfinished.append(item)
                continue
            }
            if standing.refusedOnce.insert(item.course.courseID).inserted {
                unfinished.append(item)
            } else {
                refused.append(item.course)
            }
        }
        return (unfinished, refused)
    }
}
