// CalendarForwardShiftService.swift
// "Move All Forward 1 Day" for the merged Lessons & Work calendar.
//
// The whole plan slides one school day later — presentations *and* the work
// checks alongside them. Work used to stay put while the lessons moved, which
// pulled a day in half: the presentation landed on Tuesday and the check on the
// work it produced was still sitting on Monday, so a guide who pushed the week
// had to walk the work across day by day afterwards.
//
// A service rather than another method on the calendar view, because the rule
// it encodes — what moves, how far, and what travels with it — is the part
// worth testing, and a `View` extension cannot be.

import CoreData
import Foundation

enum CalendarForwardShiftService {

    /// What a shift touched, so the caller knows whether there is anything to
    /// save.
    struct Result: Equatable {
        var presentations: Int = 0
        var checkIns: Int = 0

        var isEmpty: Bool { presentations == 0 && checkIns == 0 }
    }

    /// Moves every scheduled presentation and work check one school day later.
    ///
    /// `nextSchoolDay` is passed in rather than resolved here: it reads the
    /// school-day cache, which is a different concern from the shift itself and
    /// the one a test wants to pin down. Answers are memoized per start-of-day,
    /// since a classroom's plan lands on a handful of dates rather than one per
    /// record.
    ///
    /// Nothing is saved — the calendar owns the save coordinator.
    @discardableResult
    static func moveForwardOneDay(
        in context: NSManagedObjectContext,
        calendar: Calendar,
        nextSchoolDay: (Date) -> Date
    ) -> Result {
        var resolved: [Date: Date] = [:]
        func nextDay(after date: Date) -> Date {
            let key = calendar.startOfDay(for: date)
            if let cached = resolved[key] { return cached }
            let next = nextSchoolDay(key)
            resolved[key] = next
            return next
        }

        var result = Result()

        for assignment in scheduledPresentations(in: context) {
            guard let current = assignment.scheduledFor else { continue }
            // Carry the within-day position across, or moving the week forward
            // would flatten every day's order to a single instant.
            assignment.setScheduledFor(
                preservingTimeOfDay(from: current, onto: nextDay(after: current), using: calendar),
                using: calendar
            )
            result.presentations += 1
        }

        let checkIns = scheduledCheckIns(in: context)
        let works = worksByID(for: checkIns, in: context)
        for checkIn in checkIns {
            guard let current = checkIn.date else { continue }
            let moved = preservingTimeOfDay(from: current, onto: nextDay(after: current), using: calendar)
            checkIn.date = moved
            // The work's due date travels with its check — the same pairing a
            // single dragged pill keeps.
            if let workID = checkIn.workID.asUUID { works[workID]?.dueAt = moved }
            result.checkIns += 1
        }

        return result
    }

    /// Moves `source`'s time-of-day onto `day`, so a record keeps its position
    /// within the day when the whole plan shifts.
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

    // MARK: - What moves

    /// Everything still waiting to be given. A presentation that has already
    /// happened is a record of a day, not a plan for one.
    private static func scheduledPresentations(
        in context: NSManagedObjectContext
    ) -> [CDLessonAssignment] {
        let request = CDFetchRequest(CDLessonAssignment.self)
        request.predicate = NSPredicate(
            format: "scheduledFor != nil AND stateRaw != %@",
            LessonAssignmentState.presented.rawValue
        )
        return context.safeFetch(request)
    }

    /// Every check still waiting to happen, not only the ones in the calendar's
    /// visible window — the presentations move on those same terms.
    private static func scheduledCheckIns(
        in context: NSManagedObjectContext
    ) -> [CDWorkCheckIn] {
        let request = CDFetchRequest(CDWorkCheckIn.self)
        request.predicate = NSPredicate(
            format: "statusRaw == %@ AND date != nil",
            WorkCheckInStatus.scheduled.rawValue
        )
        return context.safeFetch(request)
    }

    /// The works a set of check-ins belongs to, in one fetch rather than one
    /// per check-in.
    private static func worksByID(
        for checkIns: [CDWorkCheckIn],
        in context: NSManagedObjectContext
    ) -> [UUID: CDWorkModel] {
        let ids = Set(checkIns.compactMap { $0.workID.asUUID })
        guard !ids.isEmpty else { return [:] }
        let request = CDFetchRequest(CDWorkModel.self)
        request.predicate = NSPredicate(format: "id IN %@", ids as NSSet)
        return Dictionary(
            context.safeFetch(request).compactMap { work in work.id.map { ($0, work) } },
            // CloudKit sync can leave duplicate rows sharing an id; first wins,
            // matching every other lookup table in the app.
            uniquingKeysWith: { first, _ in first }
        )
    }
}
