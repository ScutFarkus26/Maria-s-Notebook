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

    /// A check-in dragged to another day moves with its work's due date, so the
    /// two never drift apart.
    func rescheduleCheckIn(id: UUID, to day: Date) {
        let request: NSFetchRequest<CDWorkCheckIn> = NSFetchRequest(entityName: "WorkCheckIn")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        guard let checkIn = viewContext.safeFetchFirst(request),
              let workID = checkIn.workID.asUUID else { return }

        checkIn.date = day
        fetchWork(id: workID)?.dueAt = day
        saveCoordinator.save(viewContext, reason: "Reschedule work check-in from calendar")
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
        let checkIn = CDWorkCheckIn(context: viewContext)
        checkIn.workID = workID.uuidString
        checkIn.date = date
        checkIn.status = .scheduled
        checkIn.purpose = reason
        checkIn.studentInitiated = studentInitiated
        if !note.trimmed().isEmpty {
            checkIn.setLegacyNoteText(note, in: viewContext)
        }
        fetchWork(id: workID)?.dueAt = date
        saveCoordinator.save(viewContext, reason: "Schedule work check-in from calendar")
        Task { await refreshCheckIns() }
    }

    func fetchWork(id: UUID) -> CDWorkModel? {
        let request: NSFetchRequest<CDWorkModel> = NSFetchRequest(entityName: "WorkModel")
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        request.fetchLimit = 1
        return viewContext.safeFetch(request).first
    }

    /// Moves `source`'s time-of-day onto `day`, so a lesson keeps its position
    /// within the day when the whole week shifts.
    static func preservingTimeOfDay(
        from source: Date,
        onto day: Date,
        using calendar: Calendar
    ) -> Date {
        let time = calendar.dateComponents([.hour, .minute, .second], from: source)
        return calendar.date(
            bySettingHour: time.hour ?? UIConstants.morningHour,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: day
        ) ?? day
    }

    func clearAllScheduledLessonsToInbox() async {
        let scheduled = lessonAssignments.filter { $0.scheduledFor != nil && !$0.isGiven }
        guard !scheduled.isEmpty else { return }
        for lesson in scheduled { lesson.unschedule() }
        saveCoordinator.save(viewContext, reason: "Clear all scheduled presentations to inbox")
    }

    func moveAllScheduledLessonsForward() async {
        let scheduled = lessonAssignments.filter { $0.scheduledFor != nil && !$0.isGiven }
        guard !scheduled.isEmpty else { return }
        for lesson in scheduled {
            guard let currentDate = lesson.scheduledFor else { continue }
            let nextSchoolDay = await SchoolCalendar.nextSchoolDay(after: currentDate, using: viewContext)
            // Carry the within-day position across, or moving the week forward
            // would flatten every day's order to a single instant.
            lesson.setScheduledFor(
                Self.preservingTimeOfDay(from: currentDate, onto: nextSchoolDay, using: calendar),
                using: calendar
            )
        }
        saveCoordinator.save(viewContext, reason: "Move all scheduled presentations forward one day")
    }
}
