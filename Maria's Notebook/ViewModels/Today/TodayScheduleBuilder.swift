import Foundation
import SwiftData

// MARK: - Today Schedule Builder

/// Builder for constructing schedule items from work data.
/// Processes work items to determine overdue, due today, and stale items.
enum TodayScheduleBuilder {

    // MARK: - Types

    /// Result of processing work items for schedule display.
    struct ScheduleResult {
        let overdue: [ScheduledWorkItem]
        let today: [ScheduledWorkItem]
        let stale: [FollowUpWorkItem]
    }

    // MARK: - Build Schedule

    /// Processes work items to determine overdue, due today, and stale items.
    ///
    /// - Parameters:
    ///   - workItems: All work items to process
    ///   - checkInsByWork: Scheduled work check-ins grouped by work ID (Migration: was planItemsByWork)
    ///   - notesByWork: Notes grouped by work ID
    ///   - studentsByID: Cached students for level filtering
    ///   - levelFilter: Current level filter
    ///   - referenceDate: The date to use as "today" for calculations
    ///   - modelContext: Model context for aging policy checks
    /// - Returns: A ScheduleResult containing overdue, today, and stale items
    static func buildSchedule(
        workItems: [WorkModel],
        checkInsByWork: [UUID: [WorkCheckIn]],
        notesByWork: [UUID: [Note]],
        studentsByID: [UUID: Student],
        levelFilter: LevelFilter,
        referenceDate: Date,
        modelContext: ModelContext
    ) -> ScheduleResult {
        var newOverdue: [ScheduledWorkItem] = []
        var newToday: [ScheduledWorkItem] = []
        var newStale: [FollowUpWorkItem] = []

        let startToday = referenceDate.startOfDay

        for work in workItems {
            // Filter by Level
            if let sid = UUID(uuidString: work.studentID),
               let s = studentsByID[sid],
               !levelFilter.matches(s.level) {
                continue
            }

            let workCheckIns = checkInsByWork[work.id] ?? []
            let workNotes = notesByWork[work.id] ?? []

            // Determine Last Meaningful Touch to validate overdue status
            let checkIns = work.checkIns ?? []
            let lastTouch = WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: checkIns, notes: workNotes)
            let startLastTouch = lastTouch.startOfDay

            // Sort scheduled check-ins to find earliest relevant
            let sortedCheckIns = workCheckIns.sorted { $0.date < $1.date }

            // --- Overdue Logic ---
            // An item is overdue if its date is < Today AND last touch is BEFORE that date.
            var isOverdueOrToday = false

            if let overdueItem = sortedCheckIns.first(where: { item in
                let itemDate = item.date.startOfDay
                return itemDate < startToday && startLastTouch < itemDate
            }) {
                newOverdue.append(ScheduledWorkItem(work: work, checkIn: overdueItem))
                isOverdueOrToday = true
            }

            // --- Due Today Logic ---
            if let todayItem = sortedCheckIns.first(where: { $0.date.isSameDay(as: referenceDate) }) {
                newToday.append(ScheduledWorkItem(work: work, checkIn: todayItem))
                isOverdueOrToday = true
            }

            // --- Stale/Follow-Up Logic ---
            if !isOverdueOrToday {
                if WorkAgingPolicy.isStale(work, modelContext: modelContext, checkIns: checkIns, notes: workNotes) {
                    let days = WorkAgingPolicy.daysSinceLastTouch(for: work, modelContext: modelContext, checkIns: checkIns, notes: workNotes)
                    newStale.append(FollowUpWorkItem(work: work, daysSinceTouch: days))
                }
            }
        }

        return ScheduleResult(
            overdue: newOverdue.sorted { $0.checkIn.date < $1.checkIn.date },
            today: newToday.sorted { $0.checkIn.date < $1.checkIn.date },
            stale: Array(newStale.sorted { $0.daysSinceTouch > $1.daysSinceTouch }.prefix(15))
        )
    }
}
