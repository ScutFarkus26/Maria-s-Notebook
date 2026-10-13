import Foundation
import OSLog

// What this device last saw in ParentLocker: a change synced in (or made
// before "after"), the guide's backstops and a whole-class retry go over a
// child only while ParentLocker still holds them as this device saw them;
// anything else there was saved since by another device, maybe with a newer
// mark, and is left to it.

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
