import Foundation
import CoreData

// MARK: - Today Schedule Builder

/// Builder for constructing schedule items from work data.
/// Processes work items to determine overdue, due today, and stale items.
enum TodayScheduleBuilder {

    // MARK: - Types

    /// Result of processing work items for schedule display.
    struct ScheduleResult {
        /// The most-stale `staleRowLimit` items, longest untouched first.
        let stale: [FollowUpWorkItem]
        /// Every stale item, kept or not, so the UI can name the real number.
        let staleTotalCount: Int
    }

    /// How many stale items `stale` keeps.
    static let staleRowLimit = 15

    // MARK: - Build Schedule

    // Processes work items to determine overdue, due today, and stale items.
    //
    // - Parameters:
    //   - workItems: All work items to process
    //   - checkInsByWork: Scheduled work check-ins grouped by work ID (Migration: was planItemsByWork)
    //   - notesByWork: Notes grouped by work ID
    //   - studentsByID: Cached students for level filtering
    //   - levelFilter: Current level filter
    //   - referenceDate: The date to use as "today" for calculations
    //   - context: Managed object context for aging policy checks
    // - Returns: A ScheduleResult containing overdue, today, and stale items
    // swiftlint:disable:next function_parameter_count
    static func buildSchedule(
        workItems: [CDWorkModel],
        checkInsByWork: [UUID: [CDWorkCheckIn]],
        notesByWork: [UUID: [CDNote]],
        studentsByID: [UUID: CDStudent],
        levelFilter: LevelFilter,
        referenceDate: Date,
        context: NSManagedObjectContext
    ) -> ScheduleResult {
        var newStale: [FollowUpWorkItem] = []

        // Tracks work already placed in the overdue list so the due-today
        // branch can't add the same work a second time (overdue precedence).
        var placedWorkIDs: Set<UUID> = []

        let startToday = referenceDate.startOfDay

        for work in workItems {
            // Filter by Level — mirrors TodayLevelFilterService.filterWork:
            // drop the item unless its student is present in studentsByID
            // (enrolled + visible) AND matches the level filter. Items whose
            // student is missing (withdrawn, hidden test students, garbage IDs)
            // are excluded, not kept.
            guard let sid = UUID(uuidString: work.studentID),
                  let s = studentsByID[sid],
                  levelFilter.matches(s.level) else {
                continue
            }

            guard let workID = work.id else { continue }
            let workCheckIns = checkInsByWork[workID] ?? []
            let workNotes = notesByWork[workID] ?? []

            // Determine Last Meaningful Touch to validate overdue status
            let checkIns = (work.checkIns?.allObjects as? [CDWorkCheckIn]) ?? []
            let lastTouch = WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: checkIns, notes: workNotes)
            let startLastTouch = lastTouch.startOfDay

            // --- Overdue Logic ---
            // An item is overdue if its date is < Today AND last touch is BEFORE that date.
            var isOverdueOrToday = false

            if workCheckIns.contains(where: { item in
                let itemDate = (item.date ?? .distantPast).startOfDay
                return itemDate < startToday && startLastTouch < itemDate
            }) {
                placedWorkIDs.insert(workID)
                isOverdueOrToday = true
            }

            // --- Due Today Logic ---
            // Skip if this work is already placed in the overdue list so it
            // appears only once (overdue takes precedence over due-today).
            if !placedWorkIDs.contains(workID),
               workCheckIns.contains(where: { ($0.date ?? .distantPast).isSameDay(as: referenceDate) }) {
                isOverdueOrToday = true
            }

            // --- Stale/Follow-Up Logic ---
            if !isOverdueOrToday && !hasUpcomingCheckIn(checkIns + workCheckIns, after: startToday) {
                if WorkAgingPolicy.isStale(work, using: context, checkIns: checkIns, notes: workNotes) {
                    let days = WorkAgingPolicy.daysSinceLastTouch(
                        for: work, using: context,
                        checkIns: checkIns, notes: workNotes
                    )
                    newStale.append(FollowUpWorkItem(work: work, daysSinceTouch: days))
                }
            }
        }

        return ScheduleResult(
            stale: Array(newStale.sorted { $0.daysSinceTouch > $1.daysSinceTouch }.prefix(staleRowLimit)),
            staleTotalCount: newStale.count
        )
    }

    /// A check-in still ahead is a plan, not silence: scheduling one from a
    /// Gone quiet row takes the row off the list.
    private static func hasUpcomingCheckIn(_ checkIns: [CDWorkCheckIn], after startToday: Date) -> Bool {
        checkIns.contains { checkIn in
            checkIn.status == .scheduled && (checkIn.date ?? .distantPast).startOfDay > startToday
        }
    }
}
