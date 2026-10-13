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

    /// `refreshStatus` with today as `state` holds it.
    func refreshStatus(_ state: ParentLockerDay) {
        guard state.method == .parentLocker else { return status = ParentLockerStatus(state: .off) }
        guard isSignedIn else { return status = ParentLockerStatus(state: .signedOut) }
        if let stop = signInStop {
            if status.state != stop { status = ParentLockerStatus(state: stop) }
            return
        }
        guard let keepsProblems = quieting(ranToday: status.lastSyncAt.map(isToday) ?? false) else { return }
        if keepsProblems {
            status.state = quietState(state)
        } else {
            status = ParentLockerStatus(state: quietState(state))
        }
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
        let problems = result.notExpected ? [] : ParentLockerStatus.problems(
            for: result.plan.skipped, names: day.name(of:), isGuide: day.role == .leadGuide
        ) + result.conflicts
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
}

/// How one run went: what it sent (or why not), and the status it ends on.
nonisolated struct ParentLockerRunOutcome: Sendable {
    let result: Result<ParentLockerReport, ParentLockerSendFailure>
    let status: ParentLockerStatus
}
