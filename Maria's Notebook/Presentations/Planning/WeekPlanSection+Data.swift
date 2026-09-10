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

    func reloadDays() async {
        startDateRaw = startDate.timeIntervalSinceReferenceDate
        days = SchoolDayChecker.nextSchoolDays(
            from: startDate,
            count: Self.visibleDayCount,
            using: viewContext
        )
        await refreshCheckIns()
    }

    func moveStart(bySchoolDays delta: Int) {
        guard delta != 0 else { return }
        var remaining = abs(delta)
        var cursor = AppCalendar.startOfDay(startDate)
        let step = delta > 0 ? 1 : -1
        while remaining > 0 {
            cursor = calendar.date(byAdding: .day, value: step, to: cursor) ?? cursor
            if SchoolDayChecker.isSchoolDay(cursor, using: viewContext) { remaining -= 1 }
        }
        startDate = cursor
    }

    func scrollToFirstDay(_ proxy: ScrollViewProxy) {
        guard focusedPresentationID == nil, let first = days.first else { return }
        adaptiveWithAnimation { proxy.scrollTo(first, anchor: .leading) }
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
            // Off-screen: move the window, which reloads and re-runs this.
            if !calendar.isDate(startDate, inSameDayAs: focusedDay) {
                startDate = focusedDay
            }
            return
        }
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(50))
        guard !Task.isCancelled else { return }
        adaptiveWithAnimation { proxy.scrollTo(visibleDay, anchor: .center) }
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
        let request: NSFetchRequest<CDWorkCheckIn> = NSFetchRequest(entityName: "WorkCheckIn")
        request.predicate = NSPredicate(
            format: "statusRaw == %@ AND date >= %@ AND date < %@",
            WorkCheckInStatus.scheduled.rawValue, start as NSDate, end as NSDate
        )
        let fetched = viewContext.safeFetch(request)
        cachedCheckIns = fetched
        checkInLookup = CalendarCheckInGrouper.Lookup.build(for: fetched, in: viewContext)
    }

    // MARK: - Actions

    func openCheckInGroup(_ group: CalendarCheckInGroup) {
        if group.isGrouped {
            selectedGroup = group
        } else if let workID = group.primary.workID.asUUID {
            onOpenWork(workID)
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
