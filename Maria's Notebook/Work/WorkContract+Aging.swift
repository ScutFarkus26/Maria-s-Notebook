import Foundation
import SwiftData

// Instance conveniences that forward to WorkContractAging static helpers.
extension WorkContract {
    // MARK: - Last meaningful touch
    nonisolated func lastMeaningfulTouchDate(
        planItems: [WorkPlanItem],
        notes: [Note]? = nil,
        presentation: Presentation? = nil
    ) -> Date {
        WorkContractAging.lastMeaningfulTouchDate(
            for: self,
            planItems: planItems,
            notes: notes,
            presentation: presentation
        )
    }

    // MARK: - Days since last touch (calendar days)
    @available(*, deprecated, message: "Prefer school-day overload using ModelContext.")
    nonisolated func daysSinceLastTouch(
        planItems: [WorkPlanItem],
        notes: [Note]? = nil,
        presentation: Presentation? = nil
    ) -> Int {
        WorkContractAging.daysSinceLastTouch(
            for: self,
            planItems: planItems,
            notes: notes,
            presentation: presentation
        )
    }

    // MARK: - Days since last touch (school days)
    nonisolated func daysSinceLastTouch(
        modelContext: ModelContext,
        planItems: [WorkPlanItem],
        notes: [Note]? = nil,
        presentation: Presentation? = nil
    ) -> Int {
        WorkContractAging.daysSinceLastTouch(
            for: self,
            modelContext: modelContext,
            planItems: planItems,
            notes: notes,
            presentation: presentation
        )
    }

    // MARK: - Stale checks
    @available(*, deprecated, message: "Prefer school-day overload using ModelContext.")
    nonisolated func isStale(
        planItems: [WorkPlanItem],
        notes: [Note]? = nil,
        presentation: Presentation? = nil
    ) -> Bool {
        WorkContractAging.isStale(
            self,
            planItems: planItems,
            notes: notes,
            presentation: presentation
        )
    }

    nonisolated func isStale(
        modelContext: ModelContext,
        planItems: [WorkPlanItem],
        notes: [Note]? = nil,
        presentation: Presentation? = nil
    ) -> Bool {
        WorkContractAging.isStale(
            self,
            modelContext: modelContext,
            planItems: planItems,
            notes: notes,
            presentation: presentation
        )
    }
}
