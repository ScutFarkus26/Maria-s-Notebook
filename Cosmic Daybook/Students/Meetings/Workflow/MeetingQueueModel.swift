import Foundation
import CoreData
import Combine

// MARK: - Signals

/// What the Meetings queue knows about one child.
struct MeetingQueueSignals: Equatable {
    var lastMet: Date?
    /// The child's earliest booked meeting, individual or group.
    var scheduled: Date?
    var isAbsentToday = false
    /// Open work older than the work-overdue setting.
    var stuckWork = 0
    /// Active focus items carried from earlier meetings.
    var focusCarried = 0

    /// Days since the last meeting, counted from the school-year epoch so last
    /// spring's meeting doesn't read "104 days" on the first morning back.
    /// Nil when the child has never met.
    func daysWaiting(now: Date = Date(), calendar: Calendar = AppCalendar.shared) -> Int? {
        guard let lastMet else { return nil }
        let from = SchoolYearCounters.countFrom(lastMet)
        return max(0, calendar.dateComponents([.day], from: from, to: now).day ?? 0)
    }
}

/// How the Up Next list is ordered.
enum MeetingQueueOrder: String, CaseIterable {
    /// Booked for today or earlier, then never met, then longest wait.
    case need
    /// The order the guide dragged the rows into.
    case custom

    var label: String {
        switch self {
        case .need: "By Need"
        case .custom: "Custom Order"
        }
    }
}

// MARK: - Arranging the queue

/// The guide's queue settings.
struct MeetingQueueRules: Equatable {
    /// A child who hasn't met within this many days needs a meeting.
    var cadenceDays: Int
    /// Children put back by hand although they met recently.
    var requeued: Set<UUID> = []
    var order: MeetingQueueOrder = .need
    /// The dragged order, used when `order` is `.custom`.
    var customOrder: [UUID] = []
}

/// The queue's three groups, as student ids. Pure, so the rules are testable
/// without a store.
struct MeetingQueueArrangement: Equatable {
    var upNext: [UUID] = []
    var absent: [UUID] = []
    var met: [UUID] = []

    /// Everyone counted toward this cycle's progress.
    var total: Int { upNext.count + absent.count + met.count }

    /// Places `ids` (the children to show, in roster order) into the three groups.
    static func arrange(
        ids: [UUID],
        signals: [UUID: MeetingQueueSignals],
        rules: MeetingQueueRules,
        now: Date = Date(),
        calendar: Calendar = AppCalendar.shared
    ) -> MeetingQueueArrangement {
        let threshold = calendar.date(byAdding: .day, value: -rules.cadenceDays, to: now) ?? now
        var result = MeetingQueueArrangement()
        var needs: [UUID] = []
        for id in ids {
            let signal = signals[id] ?? MeetingQueueSignals()
            let metRecently = (signal.lastMet ?? .distantPast) >= threshold
            if metRecently && !rules.requeued.contains(id) {
                result.met.append(id)
            } else if signal.isAbsentToday {
                result.absent.append(id)
            } else {
                needs.append(id)
            }
        }
        switch rules.order {
        case .need:
            let rosterIndex = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
            let endOfToday = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            result.upNext = needs.sorted { lhs, rhs in
                let left = signals[lhs] ?? MeetingQueueSignals()
                let right = signals[rhs] ?? MeetingQueueSignals()
                let leftDue = (left.scheduled ?? .distantFuture) < endOfToday
                let rightDue = (right.scheduled ?? .distantFuture) < endOfToday
                if leftDue != rightDue { return leftDue }
                if (left.lastMet == nil) != (right.lastMet == nil) { return left.lastMet == nil }
                // The longer wait first: the older last meeting.
                if let leftMet = left.lastMet, let rightMet = right.lastMet, leftMet != rightMet {
                    return leftMet < rightMet
                }
                return (rosterIndex[lhs] ?? 0) < (rosterIndex[rhs] ?? 0)
            }
        case .custom:
            let needSet = Set(needs)
            let ordered = rules.customOrder.filter { needSet.contains($0) }
            let placed = Set(ordered)
            result.upNext = ordered + needs.filter { !placed.contains($0) }
        }
        return result
    }

    /// Late = waited at least twice the cadence (or never met).
    static func isLate(_ signal: MeetingQueueSignals, cadenceDays: Int, now: Date = Date()) -> Bool {
        guard let days = signal.daysWaiting(now: now) else { return false }
        return days >= cadenceDays * 2
    }
}

// MARK: - Model

/// Caches each child's queue signals so the Meetings queue reads dictionaries
/// instead of filtering every meeting for every child on every render. The
/// cache is rebuilt only when one of its entities changed, the day turned
/// over, or the work-overdue setting moved.
@Observable
final class MeetingQueueModel {
    private(set) var signals: [UUID: MeetingQueueSignals] = [:]
    /// Children with a meeting draft in progress (the row's pencil).
    private(set) var draftIDs: Set<UUID> = []

    @ObservationIgnored private var inputs: ManagedObjectChangeFlag?
    @ObservationIgnored private var builtFor: Stamp?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    /// Full rebuilds actually run (for tests pinning the gate).
    @ObservationIgnored private(set) var buildCount = 0

    private struct Stamp: Equatable {
        let day: Date
        let overdueDays: Int
    }

    nonisolated static let inputEntities: Set<String> = [
        "StudentMeeting", "ScheduledMeeting", "WorkModel", "StudentFocusItem", "AttendanceRecord"
    ]

    /// Saves and imports that can move a queue signal, delivered on the main
    /// run loop. Not debounced here: the view re-creates this publisher on
    /// every update, which would drop a pending debounced value, so the
    /// debounce lives in `requestRefresh`, on the model that outlives updates.
    nonisolated static func changes() -> some Publisher<Void, Never> {
        let center = NotificationCenter.default
        let entities = inputEntities
        let saves = center.publisher(for: .NSManagedObjectContextDidSave)
            // @Sendable: runs on the saving context's queue.
            .filter { @Sendable note in ManagedObjectChangeScope.saveTouches(entities, in: note.userInfo) }
            .map { @Sendable _ in () }
        let imports = center.publisher(for: .presentationDataDidChange)
            .filter { @Sendable note in
                let key = PersistentHistoryProcessor.changedEntityNamesKey
                guard let changed = note.userInfo?[key] as? Set<String> else { return true }
                return !changed.isDisjoint(with: entities)
            }
            .map { @Sendable _ in () }
        return saves.merge(with: imports)
            .receive(on: RunLoop.main)
    }

    /// Refreshes 300 ms after the last request, so a burst of saves rebuilds once.
    func requestRefresh(context: NSManagedObjectContext, workOverdueDays: Int) {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self?.refreshIfNeeded(context: context, workOverdueDays: workOverdueDays)
        }
    }

    /// Rebuilds the signals when an input moved since the last call.
    func refreshIfNeeded(context: NSManagedObjectContext, workOverdueDays: Int, now: Date = Date()) {
        let stamp = Stamp(day: AppCalendar.startOfDay(now), overdueDays: workOverdueDays)
        let moved = flag(for: context).consume(pendingIn: context)
        if moved || builtFor != stamp {
            build(context: context, stamp: stamp, now: now)
        }
    }

    func refreshDrafts() {
        let drafts = MeetingPersistenceService.studentsWithDrafts()
        if drafts != draftIDs { draftIDs = drafts }
    }

    private func flag(for context: NSManagedObjectContext) -> ManagedObjectChangeFlag {
        if let existing = inputs, existing.watches(context) { return existing }
        let flag = ManagedObjectChangeFlag(entityNames: Self.inputEntities, context: context)
        inputs = flag
        return flag
    }

    private func build(context: NSManagedObjectContext, stamp: Stamp, now: Date) {
        // Cleared before the build, so a change that lands during it counts.
        _ = flag(for: context).consume(pendingIn: context)
        builtFor = stamp
        buildCount += 1

        var result: [UUID: MeetingQueueSignals] = [:]
        Self.addMeetings(to: &result, context: context)
        Self.addBookings(to: &result, context: context)
        Self.addStuckWork(to: &result, overdueDays: stamp.overdueDays, now: now, context: context)
        Self.addFocus(to: &result, context: context)
        Self.addAbsences(to: &result, now: now, context: context)
        if result != signals { signals = result }
        refreshDrafts()
    }

    // MARK: - Sources

    private static func addMeetings(to result: inout [UUID: MeetingQueueSignals], context: NSManagedObjectContext) {
        for meeting in context.safeFetch(CDFetchRequest(CDStudentMeeting.self)) {
            guard let id = UUID(uuidString: meeting.studentID), let date = meeting.date else { continue }
            if (result[id]?.lastMet ?? .distantPast) < date {
                result[id, default: MeetingQueueSignals()].lastMet = date
            }
        }
    }

    private static func addBookings(to result: inout [UUID: MeetingQueueSignals], context: NSManagedObjectContext) {
        for booking in context.safeFetch(CDFetchRequest(CDScheduledMeeting.self)) {
            guard let date = booking.date else { continue }
            for id in booking.allStudentIDs.compactMap(UUID.init(uuidString:))
            where (result[id]?.scheduled ?? .distantFuture) > date {
                result[id, default: MeetingQueueSignals()].scheduled = date
            }
        }
    }

    private static func addStuckWork(
        to result: inout [UUID: MeetingQueueSignals], overdueDays: Int, now: Date, context: NSManagedObjectContext
    ) {
        let overdueBefore = AppCalendar.shared.date(byAdding: .day, value: -overdueDays, to: now) ?? now
        let work = CDFetchRequest(CDWorkModel.self)
        work.predicate = NSPredicate(
            format: "statusRaw IN %@ AND createdAt < %@",
            WorkStatus.openCases.map(\.rawValue), overdueBefore as NSDate
        )
        for item in context.safeFetch(work) {
            guard let id = UUID(uuidString: item.studentID) else { continue }
            result[id, default: MeetingQueueSignals()].stuckWork += 1
        }
    }

    private static func addFocus(to result: inout [UUID: MeetingQueueSignals], context: NSManagedObjectContext) {
        let focus = CDFetchRequest(CDStudentFocusItem.self)
        focus.predicate = NSPredicate(format: "statusRaw == %@", FocusItemStatus.active.rawValue)
        for item in context.safeFetch(focus) {
            guard let id = item.studentIDUUID else { continue }
            result[id, default: MeetingQueueSignals()].focusCarried += 1
        }
    }

    private static func addAbsences(
        to result: inout [UUID: MeetingQueueSignals], now: Date, context: NSManagedObjectContext
    ) {
        let attendance = CDFetchRequest(CDAttendanceRecord.self)
        attendance.predicate = NSPredicate(format: "date == %@", now.normalizedDay() as NSDate)
        for record in context.safeFetch(attendance).deduplicatedPerStudentDay() where record.status == .absent {
            guard let id = UUID(uuidString: record.studentID) else { continue }
            result[id, default: MeetingQueueSignals()].isAbsentToday = true
        }
    }
}
