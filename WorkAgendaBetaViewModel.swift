// WorkAgendaBetaViewModel.swift
// Lightweight VM/service for WorkAgendaBeta. Computes school days, fetches open works and plan items by range.

import Foundation
import SwiftData
import Combine

@MainActor
final class WorkAgendaBetaViewModel: ObservableObject {
    @Published var startDate: Date
    @Published var searchText: String = ""
    @Published var quickFilter: QuickFilter = .all

    enum QuickFilter: String, CaseIterable, Identifiable {
        case all
        case needsAttention
        case stale
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All Open"
            case .needsAttention: return "Needs Attention"
            case .stale: return "Stale"
            }
        }
    }

    init(startDate: Date = Date()) {
        let normalized = AppCalendar.startOfDay(startDate)
        self.startDate = normalized
    }

    func schoolDays(count: Int, using context: ModelContext) -> [Date] {
        var days: [Date] = []
        var d = startDate
        let cal = AppCalendar.shared
        while days.count < count {
            if !SchoolCalendar.isNonSchoolDay(d, using: context) { days.append(d) }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return days
    }

    func nextWeek(using context: ModelContext) {
        let cal = AppCalendar.shared
        var advanced = startDate
        var added = 0
        while added < 5 { // move by 5 school days
            advanced = cal.date(byAdding: .day, value: 1, to: advanced) ?? advanced
            if !SchoolCalendar.isNonSchoolDay(advanced, using: context) { added += 1 }
        }
        startDate = advanced
    }

    func previousWeek(using context: ModelContext) {
        let cal = AppCalendar.shared
        var back = startDate
        var added = 0
        while added < 5 {
            back = cal.date(byAdding: .day, value: -1, to: back) ?? back
            if !SchoolCalendar.isNonSchoolDay(back, using: context) { added += 1 }
        }
        startDate = back
    }

    func resetToToday(using context: ModelContext) {
        startDate = AgendaSchoolDayRules.computeInitialStartDate(calendar: AppCalendar.shared, isNonSchoolDay: { SchoolCalendar.isNonSchoolDay($0, using: context) })
    }

    // MARK: - Fetch helpers

    func fetchOpenWorks(context: ModelContext) -> [WorkContract] {
        // Use SwiftData fetch with predicate to avoid faulting loops
        let pred = #Predicate<WorkContract> { wc in wc.statusRaw != "complete" }
        let sort = [SortDescriptor(\WorkContract.createdAt, order: .forward)]
        let fetch = FetchDescriptor<WorkContract>(predicate: pred, sortBy: sort)
        return (try? context.fetch(fetch)) ?? []
    }

    func fetchPlanItems(in range: Range<Date>, context: ModelContext) -> [WorkPlanItem] {
        let start = AppCalendar.startOfDay(range.lowerBound)
        let end = AppCalendar.startOfDay(range.upperBound)
        let pred = #Predicate<WorkPlanItem> { item in item.scheduledDate >= start && item.scheduledDate < end }
        let sort = [SortDescriptor(\WorkPlanItem.scheduledDate, order: .forward), SortDescriptor(\WorkPlanItem.createdAt, order: .forward)]
        let fetch = FetchDescriptor<WorkPlanItem>(predicate: pred, sortBy: sort)
        return (try? context.fetch(fetch)) ?? []
    }

    func filtered(_ works: [WorkContract], searchableTextProvider: (WorkContract) -> [String]) -> [WorkContract] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = works
        let filteredByQuery: [WorkContract]
        if q.isEmpty {
            filteredByQuery = base
        } else {
            filteredByQuery = base.filter { wc in
                let fields = searchableTextProvider(wc).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                return fields.contains { $0.contains(q) }
            }
        }
        switch quickFilter {
        case .all:
            return filteredByQuery
        case .needsAttention:
            // Heuristic: items in review state need attention
            return filteredByQuery.filter { $0.status == .review }
        case .stale:
            // Items created more than 14 days ago
            let cutoff = AppCalendar.shared.date(byAdding: .day, value: -14, to: AppCalendar.startOfDay(Date())) ?? AppCalendar.startOfDay(Date())
            return filteredByQuery.filter { $0.createdAt < cutoff }
        }
    }
}

