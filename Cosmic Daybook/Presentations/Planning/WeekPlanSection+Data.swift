// WeekPlanSection+Data.swift
// The merged calendar's day window, check-in loading, and scheduling actions.
//
// Split from the view for SwiftLint's type-length limit; the state these read
// is declared in WeekPlanSection.swift.

import SwiftUI
import CoreData

extension WeekPlanSection {

    // MARK: - Day window

    func restoredStartDate() -> Date {
        guard startDateRaw != 0 else { return AppCalendar.startOfDay(Date()) }
        return AppCalendar.startOfDay(Date(timeIntervalSinceReferenceDate: startDateRaw))
    }

    /// School days loaded either side of the anchor when the window is built,
    /// and how many more join an end the guide scrolls near.
    static let windowDaysBefore = 15
    static let windowDaysAfter = 30
    static let windowGrowth = 20
    /// How close (in days) the leading edge may come to either end of the
    /// window before more days are loaded there.
    static let windowEdgeMargin = 5

    /// Builds the window around `startDate` and puts its first school day at
    /// the leading edge.
    func reloadDays() async {
        let isSchoolDay = { SchoolDayChecker.isSchoolDay($0, using: viewContext) }
        let first = Self.shiftedStart(
            from: startDate,
            bySchoolDays: -Self.windowDaysBefore,
            calendar: calendar,
            isSchoolDay: isSchoolDay
        )
        stripSettle.releasePin()
        days = SchoolDayChecker.nextSchoolDays(
            from: first,
            count: Self.windowDaysBefore + Self.windowDaysAfter,
            using: viewContext
        )
        leadingDay = days.first { $0 >= startDate } ?? days.last
        await refreshCheckIns()
    }

    /// Days on screen now: from the leading day, as many as fit across.
    var visibleDays: [Date] {
        let count = Self.visibleColumnCount(forStripWidth: stripWidth, dayCount: Self.visibleDayCount)
        let start = leadingDay.flatMap { days.firstIndex(of: $0) } ?? 0
        return Array(days.dropFirst(start).prefix(count))
    }

    /// The leading day moved. While the guide scrolls, wait: the strip settles
    /// when the scroll comes to rest (`stripScrollPhaseChanged`). A move made
    /// for her (Today, the arrows, a fresh window) settles here instead, a
    /// moment later, so an animated one has begun and settles when it lands.
    func leadingDayChanged(proxy: ScrollViewProxy) {
        guard stripSettle.leadingDayReported(leadingDay) else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(50))
            guard stripSettle.canSettle else { return }
            settleStrip(proxy: proxy)
        }
    }

    func stripScrollPhaseChanged(_ phase: ScrollPhase, proxy: ScrollViewProxy) {
        guard stripSettle.scrollPhaseChanged(isScrolling: phase != .idle), stripSettle.canSettle else { return }
        settleStrip(proxy: proxy)
    }

    /// The longest the strip holds a day after adding days in front of it.
    static let pinCap = Duration.milliseconds(500)

    static let windowMargins = WeekPlanDayWindow.Margins(
        front: windowEdgeMargin,
        back: visibleDayCount + windowEdgeMargin
    )

    /// The strip is at rest on `leadingDay`: remember it for next launch, and
    /// load more days at an end it is near. Days added in front would carry
    /// the day on screen along with them, so it is put back explicitly, without
    /// animation, rather than trusting the scroll view to hold it.
    func settleStrip(proxy: ScrollViewProxy) {
        guard let day = leadingDay, days.contains(day) else { return }
        startDateRaw = day.timeIntervalSinceReferenceDate
        let isSchoolDay = { SchoolDayChecker.isSchoolDay($0, using: viewContext) }
        guard let growth = WeekPlanDayWindow.grown(
            days: days,
            leadingDay: day,
            margins: Self.windowMargins,
            earlierDays: { first in
                let earlierStart = Self.shiftedStart(
                    from: first, bySchoolDays: -Self.windowGrowth, calendar: calendar, isSchoolDay: isSchoolDay
                )
                return SchoolDayChecker.nextSchoolDays(from: earlierStart, count: Self.windowGrowth, using: viewContext)
            },
            laterDays: { last in
                SchoolDayChecker.nextSchoolDays(
                    from: AppCalendar.addingDays(1, to: last), count: Self.windowGrowth, using: viewContext
                )
            }
        ) else { return }
        if growth.addedInFront > 0 {
            // Hold the day: the scroll view's reports while the new days lay
            // out are its own moves, not the guide's, and must not grow the
            // window again. The hold ends when a report names the day, when a
            // scroll next comes to rest, or after the cap, whichever is first.
            stripSettle.pin(day)
            days = growth.days
            pinLeadingDay(day, proxy: proxy)
            Task {
                // Put it back again once the new days have laid out, in case
                // the first scroll ran before they had.
                await Task.yield()
                if leadingDay != day { pinLeadingDay(day, proxy: proxy) }
                try? await Task.sleep(for: Self.pinCap)
                stripSettle.releasePin(holding: day)
            }
        } else {
            days = growth.days
        }
        Task { await refreshCheckIns() }
    }

    private func pinLeadingDay(_ day: Date, proxy: ScrollViewProxy) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(day, anchor: .leading)
            leadingDay = day
        }
    }

    /// Earlier / Later: one screen of school days back or forward.
    func movePage(by pages: Int) {
        guard pages != 0, !days.isEmpty else { return }
        let count = Self.visibleColumnCount(forStripWidth: stripWidth, dayCount: Self.visibleDayCount)
        let current = leadingDay.flatMap { days.firstIndex(of: $0) } ?? 0
        let target = min(max(current + pages * count, 0), days.count - 1)
        adaptiveWithAnimation { leadingDay = days[target] }
    }

    /// Brings `day` (or the first school day after it) to the leading edge:
    /// a scroll when it is loaded, a fresh window around it when it is not.
    func jump(to day: Date) {
        let target = AppCalendar.startOfDay(day)
        if let loaded = days.first(where: { $0 >= target }),
           days.first.map({ $0 <= target }) == true {
            adaptiveWithAnimation { leadingDay = loaded }
        } else if calendar.isDate(startDate, inSameDayAs: target) {
            Task { await reloadDays() }
        } else {
            startDate = target
        }
    }

    /// The school day `delta` school days from `first`. Counted from the first
    /// day the strip shows rather than the stored start (which can be a
    /// weekend), so a page of `visibleDayCount` neither skips a school day
    /// nor shows one twice.
    static func shiftedStart(
        from first: Date,
        bySchoolDays delta: Int,
        calendar: Calendar,
        isSchoolDay: (Date) -> Bool
    ) -> Date {
        var remaining = abs(delta)
        var cursor = AppCalendar.startOfDay(first)
        let step = delta > 0 ? 1 : -1
        var iterations = 0
        while remaining > 0 && iterations < 1_000 {
            cursor = calendar.date(byAdding: .day, value: step, to: cursor) ?? cursor
            if isSchoolDay(cursor) { remaining -= 1 }
            iterations += 1
        }
        return cursor
    }

    func revealFocusedPresentation(_ proxy: ScrollViewProxy) async {
        guard let focusedPresentationID,
              let assignment = lessonAssignments.first(where: {
                  $0.id == focusedPresentationID && !$0.isGiven
              }),
              let scheduledFor = assignment.scheduledFor else {
            return
        }
        let focusedDay = AppCalendar.startOfDay(scheduledFor)
        guard let visibleDay = days.first(where: { calendar.isDate($0, inSameDayAs: focusedDay) }) else {
            // Not loaded: build a window around it, with its day leading.
            jump(to: focusedDay)
            return
        }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))
        guard !Task.isCancelled else { return }
        adaptiveWithAnimation { proxy.scrollTo(visibleDay, anchor: .center) }
    }

    // MARK: - Card data

    /// The curriculum and the roster every presentation card names, read once
    /// for the whole strip. The cards used to hold a `@FetchRequest` of each
    /// table apiece, which is a live fetched-results controller per card.
    ///
    /// Withdrawn children stay in the array on purpose: a card that still
    /// carries a departed girl's name should keep showing it rather than
    /// silently drop her chip. Test children obey the same setting they obey
    /// everywhere else.
    func refreshCardData() {
        cachedLessons = viewContext.safeFetch(CDFetchRequest(CDLesson.self))
        let allStudents: [CDStudent] = viewContext.safeFetch(CDFetchRequest(CDStudent.self))
        // DEDUPLICATION: CloudKit sync can leave two rows carrying one id.
        cachedStudents = TestStudentsFilter.filterVisible(
            allStudents,
            show: testStudents.show,
            namesRaw: testStudents.namesRaw
        ).uniqueByID
    }

    // MARK: - Check-in data

    func refreshCheckIns() async {
        guard visibleKinds.showsWork, let firstDay = days.first, let lastDay = days.last else {
            cachedCheckIns = []
            checkInLookup = CalendarCheckInGrouper.Lookup()
            return
        }
        let (start, _) = AppCalendar.dayRange(for: firstDay)
        let (_, end) = AppCalendar.dayRange(for: lastDay)
        let request = CDFetchRequest(CDWorkCheckIn.self)
        request.predicate = CalendarCheckInGrouper.scheduledPredicate(start: start, end: end)
        let fetched = viewContext.safeFetch(request)
        cachedCheckIns = fetched
        checkInLookup = CalendarCheckInGrouper.Lookup.build(for: fetched, in: viewContext)
    }

    // MARK: - Actions

    /// Every pill opens the log sheet — one child or six. A single child used
    /// to jump straight to the work window, which had no way to log the check.
    func openCheckInGroup(_ group: CalendarCheckInGroup) {
        selectedGroup = group
    }

    // MARK: - Logging

    /// The rows under a pill, one per child — what its menu and sheet act on.
    func rows(of group: CalendarCheckInGroup) -> [CDWorkModel] {
        WorkCheckPillActions.rows(of: group, in: viewContext)
    }

    /// A pill's rows named for its menu's per-child submenus.
    func children(of rows: [CDWorkModel]) -> [WorkLogStatusMenu.Child] {
        WorkCheckPillActions.children(of: rows, lookup: checkInLookup)
    }

    var pillActions: WorkCheckPillActions {
        WorkCheckPillActions(
            rows: rows(of:),
            children: children(of:),
            log: { group, rows, status in
                logWork(rows.map { WorkLogService.Entry(work: $0, status: status) }, on: group.sortDate)
            },
            openWork: onOpenWork
        )
    }

    /// Logs the entries for `day`, refreshes the strip, and offers Undo.
    func logWork(_ entries: [WorkLogService.Entry], on day: Date) {
        do {
            let receipt = try WorkLogService.log(
                entries, on: day, context: viewContext, saveCoordinator: saveCoordinator
            )
            Task { await refreshCheckIns() }
            let message = receipt.rows == 1 ? "Logged 1 work check" : "Logged \(receipt.rows) work checks"
            dependencies.toastService.show(message, type: .success, duration: 5) {
                do {
                    try WorkLogService.undo(receipt.token, context: viewContext, saveCoordinator: saveCoordinator)
                } catch {
                    let message = PresentationFailureMessage.message(
                        for: error, fallback: "Couldn't undo that. Try again."
                    )
                    dependencies.toastService.show(message, type: .error, duration: 4)
                }
                Task { await refreshCheckIns() }
            }
        } catch {
            let message = PresentationFailureMessage.message(
                for: error, fallback: "Couldn't log that work check. Try again."
            )
            dependencies.toastService.show(message, type: .error, duration: 4)
        }
    }

    func clearSchedule(_ assignment: CDLessonAssignment) {
        assignment.unschedule()
        saveCoordinator.save(viewContext, reason: "Clear presentation schedule from calendar")
    }

    /// Check-ins dragged to another day move with their work's due dates, so
    /// the two never drift apart.
    ///
    /// A grouped pill hands over every check-in under it, so moving the work a
    /// lesson produced for six children is one drag and one save rather than
    /// six of each.
    func rescheduleCheckIns(ids: [UUID], to day: Date) {
        let checkIns = ids.compactMap { viewContext.object(CDWorkCheckIn.self, id: $0) }
        guard !checkIns.isEmpty else { return }

        for checkIn in checkIns {
            checkIn.date = day
            if let workID = checkIn.workID.asUUID {
                fetchWork(id: workID)?.dueAt = day
            }
        }
        saveCoordinator.save(viewContext, reason: "Reschedule work check-ins from calendar")
        Task { await refreshCheckIns() }
    }

    /// Dropping a work card asks what the check-in is for before creating it —
    /// this is the only place a check-in's purpose is ever captured.
    func beginPlanningWork(id: UUID, on day: Date) {
        prompt = WorkCheckInPlanPrompt(workID: id, date: day)
    }

    func scheduleCheckIn(
        workID: UUID,
        date: Date,
        reason: String,
        note: String,
        studentInitiated: Bool
    ) {
        // A drop onto a day used to write only the workID string; without the
        // relationship the check-in read as "Untitled work — unassigned" over
        // MCP. No work row, no check-in.
        guard let work = fetchWork(id: workID) else { return }
        let checkIn = CDWorkCheckIn.make(
            for: work, on: date, purpose: reason, studentInitiated: studentInitiated, in: viewContext
        )
        if !note.trimmed().isEmpty {
            checkIn.setLegacyNoteText(note, in: viewContext)
        }
        work.dueAt = date
        saveCoordinator.save(viewContext, reason: "Schedule work check-in from calendar")
        Task { await refreshCheckIns() }
    }

    func fetchWork(id: UUID) -> CDWorkModel? {
        viewContext.object(CDWorkModel.self, id: id)
    }

    func clearAllScheduledLessonsToInbox() async {
        let scheduled = lessonAssignments.filter { $0.scheduledFor != nil && !$0.isGiven }
        guard !scheduled.isEmpty else { return }
        for lesson in scheduled { lesson.unschedule() }
        saveCoordinator.save(viewContext, reason: "Clear all scheduled presentations to inbox")
    }

    /// Slides the whole plan one school day later — presentations and the work
    /// checks alongside them. See `CalendarForwardShiftService` for the rule.
    func moveAllScheduledForward() async {
        let moved = CalendarForwardShiftService.moveForwardOneDay(
            in: viewContext,
            calendar: calendar,
            nextSchoolDay: { day in
                SchoolCalendarService.shared.nextSchoolDaySync(after: day, using: viewContext)
            }
        )
        guard !moved.isEmpty else { return }
        saveCoordinator.save(
            viewContext,
            reason: "Move all scheduled presentations and work forward one day"
        )
        await refreshCheckIns()
    }
}
