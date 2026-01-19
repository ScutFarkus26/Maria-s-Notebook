import Foundation
import SwiftData

// MARK: - Today Schedule Builder

/// Builder for constructing schedule items from work data.
/// Processes work items to determine overdue, due today, and stale items.
enum TodayScheduleBuilder {

    // MARK: - Types

    /// Result of processing work items for schedule display.
    struct ScheduleResult {
        let overdue: [ContractScheduleItem]
        let today: [ContractScheduleItem]
        let stale: [ContractFollowUpItem]
    }

    // MARK: - Build Schedule

    /// Processes work items to determine overdue, due today, and stale items.
    ///
    /// - Parameters:
    ///   - workItems: All work items to process
    ///   - planItemsByWork: Work plan items grouped by work ID
    ///   - notesByWork: Notes grouped by work ID
    ///   - studentsByID: Cached students for level filtering
    ///   - levelFilter: Current level filter
    ///   - referenceDate: The date to use as "today" for calculations
    ///   - modelContext: Model context for aging policy checks
    /// - Returns: A ScheduleResult containing overdue, today, and stale items
    static func buildSchedule(
        workItems: [WorkModel],
        planItemsByWork: [UUID: [WorkPlanItem]],
        notesByWork: [UUID: [Note]],
        studentsByID: [UUID: Student],
        levelFilter: LevelFilter,
        referenceDate: Date,
        modelContext: ModelContext
    ) -> ScheduleResult {
        var newOverdue: [ContractScheduleItem] = []
        var newToday: [ContractScheduleItem] = []
        var newStale: [ContractFollowUpItem] = []

        let startToday = referenceDate.startOfDay

        for work in workItems {
            // Filter by Level
            if let sid = UUID(uuidString: work.studentID),
               let s = studentsByID[sid],
               !levelFilter.matches(s.level) {
                continue
            }

            let workPlans = planItemsByWork[work.id] ?? []
            let workNotes = notesByWork[work.id] ?? []

            // Determine Last Meaningful Touch to validate overdue status
            let checkIns = work.checkIns ?? []
            let lastTouch = WorkAgingPolicy.lastMeaningfulTouchDate(for: work, checkIns: checkIns, notes: workNotes)
            let startLastTouch = lastTouch.startOfDay

            // Sort plans to find earliest relevant
            let sortedPlans = workPlans.sorted { $0.scheduledDate < $1.scheduledDate }

            // --- Overdue Logic ---
            // An item is overdue if its date is < Today AND last touch is BEFORE that date.
            var isOverdueOrToday = false

            if let overdueItem = sortedPlans.first(where: { item in
                let itemDate = item.scheduledDate.startOfDay
                return itemDate < startToday && startLastTouch < itemDate
            }) {
                newOverdue.append(ContractScheduleItem(work: work, planItem: overdueItem))
                isOverdueOrToday = true
            }

            // --- Due Today Logic ---
            if let todayItem = sortedPlans.first(where: { $0.scheduledDate.isSameDay(as: referenceDate) }) {
                newToday.append(ContractScheduleItem(work: work, planItem: todayItem))
                isOverdueOrToday = true
            }

            // --- Stale/Follow-Up Logic ---
            if !isOverdueOrToday {
                if WorkAgingPolicy.isStale(work, modelContext: modelContext, checkIns: checkIns, notes: workNotes) {
                    let days = WorkAgingPolicy.daysSinceLastTouch(for: work, modelContext: modelContext, checkIns: checkIns, notes: workNotes)
                    newStale.append(ContractFollowUpItem(work: work, daysSinceTouch: days))
                }
            }
        }

        return ScheduleResult(
            overdue: newOverdue.sorted { $0.planItem.scheduledDate < $1.planItem.scheduledDate },
            today: newToday.sorted { $0.planItem.scheduledDate < $1.planItem.scheduledDate },
            stale: Array(newStale.sorted { $0.daysSinceTouch > $1.daysSinceTouch }.prefix(15))
        )
    }
}
