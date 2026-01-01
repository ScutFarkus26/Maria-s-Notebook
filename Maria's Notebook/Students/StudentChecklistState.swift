import Foundation
import Combine
import SwiftUI
import SwiftData

public struct StudentChecklistRowState: Identifiable, Equatable {
    public var id: UUID { lessonID }
    public let lessonID: UUID
    public let plannedItemID: UUID?
    public let presentationLogID: UUID?
    public let contractID: UUID?
    public let isScheduled: Bool
    public let isPresented: Bool
    public let isActive: Bool
    public let isComplete: Bool
    public let lastActivityDate: Date?
    public let isStale: Bool

    public init(
        lessonID: UUID,
        plannedItemID: UUID?,
        presentationLogID: UUID?,
        contractID: UUID?,
        isScheduled: Bool,
        isPresented: Bool,
        isActive: Bool,
        isComplete: Bool,
        lastActivityDate: Date?,
        isStale: Bool
    ) {
        self.lessonID = lessonID
        self.plannedItemID = plannedItemID
        self.presentationLogID = presentationLogID
        self.contractID = contractID
        self.isScheduled = isScheduled
        self.isPresented = isPresented
        self.isActive = isActive
        self.isComplete = isComplete
        self.lastActivityDate = lastActivityDate
        self.isStale = isStale
    }
}

@MainActor
final class StudentChecklistViewModel: ObservableObject {
    @Published var rowStatesByLesson: [UUID: StudentChecklistRowState] = [:]

    let studentID: UUID

    private var staleThresholdDays: Int {
        (UserDefaults.standard.object(forKey: "Planning.staleThresholdDays") as? Int) ?? 8
    }

    init(studentID: UUID) {
        self.studentID = studentID
    }

    /// Recompute derived row states for the provided lessons in bulk, minimizing fetches.
    func recompute(for lessons: [Lesson], using context: ModelContext) {
        let lessonIDs: [UUID] = lessons.map { $0.id }
        guard !lessonIDs.isEmpty else {
            rowStatesByLesson = [:]
            return
        }

        let lessonIDsSet = Set(lessonIDs)

        // Fetch StudentLessons once
        let slFetch = FetchDescriptor<StudentLesson>(
            predicate: #Predicate { sl in
                lessonIDsSet.contains(sl.lessonID)
            }
        )
        let allSLs: [StudentLesson] = (try? context.fetch(slFetch)) ?? []
        let studentIDString = self.studentID.uuidString
        let allSLsForStudent: [StudentLesson] = allSLs.filter { $0.studentIDs.contains(studentIDString) }

        // Non-given count as inbox/planned
        let nonGivenByLesson = Dictionary(grouping: allSLsForStudent.filter { !$0.isGiven }) { $0.lessonID }
        // Presented logs: given or explicitly marked presented
        let presentedSLs = allSLsForStudent.filter { $0.isPresented || $0.givenAt != nil }
        let presentationsByLesson: [UUID: StudentLesson] = {
            let grouped = Dictionary(grouping: presentedSLs, by: { $0.lessonID })
            let pairs: [(UUID, StudentLesson)] = grouped.compactMap { (key, group) in
                guard let mostRecent = group.max(by: { lhs, rhs in
                    Self.presentationSortKey(lhs) < Self.presentationSortKey(rhs)
                }) else { return nil }
                return (key, mostRecent)
            }
            return Dictionary(uniqueKeysWithValues: pairs)
        }()

        // Fetch WorkContracts once for this student across lessons
        let studentKey = studentID.uuidString
        // Removed previous fetch with Contains
        let wcFetch = FetchDescriptor<WorkContract>(predicate: #Predicate { c in c.studentID == studentKey })
        let allContractsForStudent: [WorkContract] = (try? context.fetch(wcFetch)) ?? []
        let contracts: [WorkContract] = allContractsForStudent.filter { contract in
            if let lid = UUID(uuidString: contract.lessonID) { return lessonIDs.contains(lid) }
            return false
        }

        // Index contracts
        let contractsByLesson: [String: [WorkContract]] = Dictionary(grouping: contracts, by: { $0.lessonID })

        // Open/Completed pickers per lesson
        var openByLesson: [String: WorkContract] = [:]
        var completedByLesson: [String: WorkContract] = [:]
        for (key, arr) in contractsByLesson {
            if let open = arr.first(where: { $0.status == .active || $0.status == .review }) {
                openByLesson[key] = open
            }
            if let comp = arr.first(where: { $0.status == .complete }) {
                completedByLesson[key] = comp
            }
        }

        // Fetch plan items for all relevant contracts in one go
        let allContractIDs: [UUID] = Array(Set(contracts.map { $0.id }))
        let planItems: [WorkPlanItem]
        if allContractIDs.isEmpty {
            planItems = []
        } else {
            let fetch = FetchDescriptor<WorkPlanItem>(predicate: #Predicate { item in allContractIDs.contains(item.workID) })
            planItems = (try? context.fetch(fetch)) ?? []
        }
        let planItemsByContract: [UUID: [WorkPlanItem]] = Dictionary(grouping: planItems, by: { $0.workID })

        // Build states per lessonID
        var result: [UUID: StudentChecklistRowState] = [:]
        let today = AppCalendar.startOfDay(Date())

        for lessonID in lessonIDs {
            let lessonKey = lessonID.uuidString

            // Planned selection among non-given SLs (inbox + scheduled)
            let nonGiven = nonGivenByLesson[lessonID] ?? []
            let plannedCandidate = nonGiven.sorted(by: { lhs, rhs in
                let lKey = Self.planSortKey(lhs)
                let rKey = Self.planSortKey(rhs)
                return lKey < rKey
            }).first

            // Presentation selection
            let presentation = presentationsByLesson[lessonID]

            // Contracts
            let open = openByLesson[lessonKey]
            let completed = completedByLesson[lessonKey]
            let contractForID = open ?? completed

            // lastActivityDate and isStale
            var lastActivity: Date? = nil
            var stale = false
            if let c = open ?? completed {
                // latest past scheduled date among plan items for this contract
                let pastPlanDates: [Date] = (planItemsByContract[c.id] ?? [])
                    .map { AppCalendar.startOfDay($0.scheduledDate) }
                    .filter { $0 <= today }
                let latestPast = pastPlanDates.max()
                lastActivity = maxDate(latestPast, AppCalendar.startOfDay(c.createdAt))
                if c.status == .complete {
                    stale = false
                } else if let last = lastActivity {
                    let days = Self.wholeDays(from: last, to: today)
                    stale = days >= staleThresholdDays
                } else {
                    stale = false
                }
            }

            // Booleans
            let isScheduled = plannedCandidate != nil
            let isPresented = (presentation != nil)
            let isActive = (open != nil)
            let isComplete = (open == nil && completed != nil)

            let state = StudentChecklistRowState(
                lessonID: lessonID,
                plannedItemID: plannedCandidate?.id,
                presentationLogID: presentation?.id,
                contractID: contractForID?.id,
                isScheduled: isScheduled,
                isPresented: isPresented,
                isActive: isActive,
                isComplete: isComplete,
                lastActivityDate: lastActivity,
                isStale: stale
            )
            result[lessonID] = state
        }

        self.rowStatesByLesson = result
    }

    // MARK: - Helpers
    private static func presentationSortKey(_ sl: StudentLesson) -> Date {
        return sl.givenAt ?? sl.scheduledFor ?? sl.createdAt
    }

    private static func planSortKey(_ sl: StudentLesson) -> Date {
        // Prefer earliest scheduled date; otherwise earliest createdAt
        return sl.scheduledFor ?? sl.createdAt
    }

    private func maxDate(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case (nil, nil): return nil
        case (let x?, nil): return x
        case (nil, let y?): return y
        case (let x?, let y?): return max(x, y)
        }
    }

    private static func wholeDays(from start: Date, to end: Date) -> Int {
        var days = 0
        var cursor = AppCalendar.startOfDay(start)
        let endDay = AppCalendar.startOfDay(end)
        while cursor < endDay {
            cursor = AppCalendar.addingDays(1, to: cursor)
            days += 1
            if days > 36500 { break }
        }
        return max(0, days)
    }
}
private extension Array {
    func group<Key: Hashable>(by key: (Element) -> Key) -> [Key: [Element]] {
        Dictionary(grouping: self, by: key)
    }
}

#if DEBUG
extension StudentChecklistViewModel {
    func debugDumpStates(for lessons: [Lesson]) -> String {
        let ids = lessons.map { $0.id }
        let dict = rowStatesByLesson.filter { ids.contains($0.key) }
        let df = DateFormatter(); df.dateStyle = .short
        return dict.keys.sorted { $0.uuidString < $1.uuidString }.map { lid in
            if let row = dict[lid] {
                let last = row.lastActivityDate.map { df.string(from: $0) } ?? "nil"
                return "\(lid.short) sched=\(row.isScheduled) pres=\(row.isPresented) active=\(row.isActive) complete=\(row.isComplete) stale=\(row.isStale) last=\(last)"
            }
            return "\(lid.short) — missing"
        }.joined(separator: "\n")
    }
}

private extension UUID {
    var short: String { self.uuidString.prefix(6) + "…" }
}
#endif

