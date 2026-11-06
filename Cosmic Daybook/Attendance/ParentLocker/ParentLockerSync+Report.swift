import Foundation

// What the sync says: the line while nothing is under way, which classes a
// run reads, and the report a whole-day send or preview gives MCP and the
// Debug preview.

extension ParentLockerSync {

    // MARK: - The line

    /// Brings the line up to date with the day while nothing is under way:
    /// off, signed out, a sign-in only a person can make, waiting for
    /// arrival (or, with everyone marked, ready to send), or as the last run
    /// left it. A run from another day says nothing about this one, its
    /// problems included.
    func refreshStatus() {
        refreshStatus(store.day(today, withChildren: false))
    }

    /// `refreshStatus` with today as `state` holds it. Attendance going by
    /// email asks for no ParentLocker sign-in (bug hunt 2026-11-05 #15).
    func refreshStatus(_ state: ParentLockerDay) {
        guard state.method == .parentLocker else {
            awaitsSignIn = false
            return status = ParentLockerStatus(state: .off)
        }
        guard isSignedIn else { return status = ParentLockerStatus(state: .signedOut) }
        if let stop = signInStop {
            if status.state != stop { status = ParentLockerStatus(state: stop) }
            return
        }
        guard let keepsProblems = quieting(ranToday: status.lastSyncAt.map(isToday) ?? false) else { return }
        if keepsProblems {
            status.state = quietState(state)
        } else {
            status = ParentLockerStatus(state: quietState(state), problems: todaysStanding)
        }
    }

    /// Today's lines that stand until a run shows them fixed (review of the
    /// 2026-11-05 fixes, E7, W2); none once the day has moved on.
    var todaysStanding: [String] {
        owedDay.map(isToday) == true ? standing.lines : []
    }

    /// How the line as it stands meets the day now: nil keeps it; true moves
    /// it to the quiet state with today's problems; false starts it afresh.
    /// A run's problems are its day's (bug hunt 2026-10-13 afternoon, M3), and
    /// with nothing left to send there's nothing to warn about (L9).
    private func quieting(ranToday: Bool) -> Bool? {
        switch status.state {
        case .off, .signedOut, .waitingForArrival, .readyToSend, .idle: ranToday
        case .upToDate, .previewed, .notExpected: ranToday ? nil : false
        case .retrying, .gaveUp, .notSentYet: ranToday && owesWork ? nil : false
        // Signed in again since, here or with a password saved elsewhere.
        case .passwordRefused, .needsYou: false
        default: nil
        }
    }

    /// What only a sign-in through the sheet clears: a saved password
    /// ParentLocker refused, or a sign-in ParentLocker wants a person for.
    private var signInStop: ParentLockerStatus.State? {
        if savedPasswordRefused { return .passwordRefused }
        return signInNeedsYou ? .needsYou : nil
    }

    /// Something is still to go: a retry, a whole-class send, or changes.
    var owesWork: Bool {
        retry != nil || wholeClass != nil || !localChanges.isEmpty || !catchUpChildren.isEmpty
            || !importedChildren.isEmpty || earlyLocalDue != nil
    }

    /// Today's whole-class send still owed, as what's owed keeps it: waiting,
    /// waiting to retry, or under way, so a mark made during a run or a
    /// retry's wait doesn't write it off (bug hunt 2026-11-05 #2). Today's
    /// Close Arrival & Send still to go is kept as that, whatever else is
    /// owed with it, so its Undo still stops it after a relaunch; then a
    /// Send Now's (or MCP's), so its rule stays (review of the fixes, E4,
    /// E8). A backstop's is kept as a send owed, as before.
    var owedWholeClass: ParentLockerWholeClass.Reason? {
        if closeArrivalPending { return .closeArrival }
        let pending = [retry?.job, runningJob].compactMap(\.self).filter {
            $0.isWholeClass && !$0.preview && isToday($0.day)
        }
        let asked = pending.contains { $0.reason == .sendNow || $0.reason == .request }
        if wholeClass?.reason == .sendNow || asked { return .sendNow }
        return wholeClass != nil || !pending.isEmpty ? .owed : nil
    }

    /// Whether `job` is today's Close Arrival & Send: its own run, or a
    /// whole-class send that goes while it's still to go (E1, W6).
    func coversCloseArrival(_ job: ParentLockerJob) -> Bool {
        guard job.isWholeClass, !job.preview, isToday(job.day) else { return false }
        return job.reason == .closeArrival || closeArrivalPending
    }

    /// Brings `closeArrivalSendUnderWay` up to date, only when it changes.
    func refreshUnderWay() {
        let underWay = closeArrivalRuns.underWay
        if closeArrivalSendUnderWay != underWay { closeArrivalSendUnderWay = underWay }
    }

    /// Today's Close Arrival & Send is still to go: waiting (out its Undo,
    /// or for a sign-in), waiting to retry, under way, or owed.
    var closeArrivalPending: Bool {
        wholeClass?.reason == .closeArrival
            || retry.map { $0.job.reason == .closeArrival && isToday($0.job.day) } ?? false
            || runningJob.map { $0.reason == .closeArrival && !$0.preview && isToday($0.day) } ?? false
    }

    /// Brings `closeArrivalSendUnsent` (and `closeArrivalSendUnderWay`) up
    /// to date, only when it changes.
    func refreshCloseArrivalUnsent() {
        let unsent = closeArrivalPending && !closeArrivalBatchSent
        if closeArrivalSendUnsent != unsent { closeArrivalSendUnsent = unsent }
        refreshUnderWay()
    }

    /// The state a run that reached ParentLocker ends on: a whole-class
    /// send's, up to date once it found the class; a live update's, up to
    /// date only while no whole-class send of today's is owed, so a class
    /// owed once its retries ran out still says so (review of the 2026-11-05
    /// fixes, E3).
    func endState(_ job: ParentLockerJob, matchedAny: Bool) -> ParentLockerStatus.State {
        if job.isWholeClass { return matchedAny ? .upToDate : .idle }
        guard isToday(job.day), let wholeClass, wholeClass.reason != .backstop else { return .upToDate }
        return wholeClass.due == nil ? .gaveUp : .idle
    }

    /// Today's lines after `job`'s run (E7, W2): each child it compared has
    /// their line replaced by what it found, and the others' stand. A child
    /// not found while a class wouldn't open wasn't compared. A class
    /// ParentLocker refused twice stands until a whole-class send reads it
    /// again.
    func updateStanding(_ job: ParentLockerJob, day: ParentLockerDay, result: ParentLockerRunResult) -> [String] {
        let onRoll = Set(day.children.map(\.id))
        let notFound = result.refusedClasses.isEmpty
            ? [] : Set(result.plan.skipped.filter { $0.reason == .unmatched }.map(\.childID))
        let compared = (job.children ?? onRoll).subtracting(result.leftToOthers).subtracting(notFound)
        let fresh = result.plan.skipped.filter {
            compared.contains($0.childID) && $0.reason != .unmarked && $0.reason != .leftOut
        }
        standing.skips = standing.skips.filter { onRoll.contains($0.childID) && !compared.contains($0.childID) }
            + fresh
        for roster in result.rosters {
            standing.refusedOnce.remove(roster.course.courseID)
            if job.isWholeClass { standing.refused[roster.course.courseID] = nil }
        }
        for course in result.refusedClasses { standing.refused[course.courseID] = course.name }
        let refusedLines = standing.refused.sorted { $0.key < $1.key }
            .map { ParentLockerStatus.refusedClassLine($0.value) }
        standing.lines = ParentLockerStatus.problems(
            for: standing.skips, names: day.name(of:), isGuide: day.role == .leadGuide
        ) + refusedLines
        return standing.lines
    }

    /// The line while nothing is under way: on a day ParentLocker isn't
    /// expecting, that, as any device of the class found it; quiet once the
    /// day is "after" (or not a school day); before, waiting for arrival,
    /// or, with everyone marked and so no Close Arrival to tap, ready to send
    /// (bug hunt 2026-10-13 afternoon, M2, M8).
    private func quietState(_ state: ParentLockerDay) -> ParentLockerStatus.State {
        if state.notExpected, state.isSchoolDay { return .notExpected }
        guard state.isSchoolDay, !isAfter(state, on: today) else { return .idle }
        let marked = state.children.isEmpty ? store.day(today, withChildren: true) : state
        return marked.everyoneMarked ? .readyToSend : .waitingForArrival
    }

    /// The children on `day`'s roll with no mark yet, as the class reads them
    /// ("Maya S"), for a screen or the Shortcut to ask about before a send:
    /// a send goes without them and doesn't count as the day's (bug hunt
    /// 2026-10-13 afternoon, M4). The guide's "Not matched" children never
    /// go to ParentLocker, so they aren't asked about.
    func unmarkedNames(on day: Date) -> [String] {
        store.day(day, withChildren: true).unmarkedNames
    }

    // MARK: - The classes a run reads

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
            } else if isToday, course.reportStatus == notExpectedStatus {
                leftAlone.append("Skipped \(course.name): no attendance is expected today.")
            } else {
                load.append(course)
            }
        }
        return (load, leftAlone)
    }

    /// Whether every daily-attendance class of today's page says ParentLocker
    /// isn't expecting attendance: a day with nothing due.
    nonisolated static func expectsNoAttendance(_ courses: [ParentLockerCourse]) -> Bool {
        let daily = courses.filter { $0.isDailyAttendance && $0.hasAttendance }
        return !daily.isEmpty && daily.allSatisfy { $0.reportStatus == notExpectedStatus }
    }

    nonisolated static let notExpectedStatus = "not_expected"

    // MARK: - Report

    /// What `job` sent or would send, in words: per class, the children
    /// unmarked (a whole day's), and what it left alone.
    func makeReport(
        _ job: ParentLockerJob, day: ParentLockerDay, result: ParentLockerRunResult
    ) -> ParentLockerReport {
        // One ParentLocker child is never reported as two of ours (A2).
        let childByStudent = ParentLockerPlanner.childByStudentID(result.matches)
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
        // A class ParentLocker wouldn't open is named, not its children as unmatched (E7).
        let shut = result.refusedClasses
        let skipped = shut.isEmpty ? result.plan.skipped : result.plan.skipped.filter { $0.reason != .unmatched }
        let problems = result.notExpected ? [] : ParentLockerStatus.problems(
            for: skipped, names: day.name(of:), isGuide: day.role == .leadGuide
        ) + shut.map { ParentLockerStatus.refusedClassLine($0.name) } + result.conflicts
        let unmarked = job.isWholeClass && !result.notExpected ? day.unmarkedNames : []
        let asked = job.reason == .sendNow || job.reason == .request
        return ParentLockerReport(
            day: job.day, wasPreview: result.wasPreview, classes: classes, problems: problems,
            classesLeftAlone: result.leftAlone, savedCount: result.savedCount, unmarked: unmarked,
            waitsForMarks: asked && !result.wasPreview && !unmarked.isEmpty && !day.sentToParentLocker,
            notExpected: result.notExpected
        )
    }

    static func conflictLine(
        _ conflict: ParentLockerSaveReply.Conflict, batch: ParentLockerPlanner.Batch,
        rosters: [ParentLockerRoster], day: ParentLockerDay
    ) -> String {
        let childID = batch.entries.first { $0.studentID == conflict.studentID }?.childID
        let marks = rosters.first { $0.course == batch.course }?.marks ?? []
        let current = marks.first { $0.id == conflict.currentMarkID }?.name
        return ParentLockerStatus.conflictLine(name: childID.map(day.name(of:)) ?? "a child", currentMark: current)
    }
}

/// What one run found and did.
struct ParentLockerRunResult {
    let plan: ParentLockerPlanner.Plan
    let rosters: [ParentLockerRoster]
    let matches: [UUID: ParentLockerPlanner.Match]
    let leftAlone: [String]
    let conflicts: [String]
    let savedCount: Int
    let wasPreview: Bool
    /// Children left to another device, which saved them in ParentLocker
    /// since this device last looked.
    let leftToOthers: Set<UUID>
    /// Today, every class said ParentLocker isn't expecting attendance.
    var notExpected = false
    /// Classes ParentLocker refused to open again today: passed over, named
    /// on the line (review of the 2026-11-05 fixes, E7).
    var refusedClasses: [ParentLockerCourse] = []
}

/// How one run went: what it sent (or why not), and the status it ends on.
nonisolated struct ParentLockerRunOutcome: Sendable {
    let result: Result<ParentLockerReport, ParentLockerSendFailure>
    let status: ParentLockerStatus
}
