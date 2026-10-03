import Foundation
import Testing
@testable import CosmicDaybook

// The Meetings queue's rules: who needs a meeting, who is absent or met, and
// the order Up Next is shown in.
@Suite("Meeting queue arrangement")
struct MeetingQueueArrangementTests {
    private let calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 10))!
    }

    private func daysAgo(_ days: Int) -> Date {
        calendar.date(byAdding: .day, value: -days, to: now)!
    }

    private func arrange(
        _ ids: [UUID],
        _ signals: [UUID: MeetingQueueSignals],
        rules: MeetingQueueRules = MeetingQueueRules(cadenceDays: 7)
    ) -> MeetingQueueArrangement {
        MeetingQueueArrangement.arrange(ids: ids, signals: signals, rules: rules, now: now, calendar: calendar)
    }

    @Test("A child met within the cadence is met; older, never, and absent children are not")
    func splitsByCadenceAndAttendance() {
        let recent = UUID(), old = UUID(), never = UUID(), absent = UUID()
        let result = arrange([recent, old, never, absent], [
            recent: MeetingQueueSignals(lastMet: daysAgo(3)),
            old: MeetingQueueSignals(lastMet: daysAgo(12)),
            absent: MeetingQueueSignals(lastMet: daysAgo(20), isAbsentToday: true)
        ])
        #expect(result.met == [recent])
        #expect(result.absent == [absent])
        #expect(Set(result.upNext) == [old, never])
        #expect(result.total == 4)
    }

    @Test("An absent child who met recently counts as met, not absent")
    func absentButMetIsMet() {
        let child = UUID()
        let result = arrange([child], [child: MeetingQueueSignals(lastMet: daysAgo(2), isAbsentToday: true)])
        #expect(result.met == [child])
        #expect(result.absent.isEmpty)
    }

    @Test("A child put back by hand waits again although she met recently")
    func requeuedChildNeedsMeeting() {
        let child = UUID()
        let result = arrange(
            [child],
            [child: MeetingQueueSignals(lastMet: daysAgo(1))],
            rules: MeetingQueueRules(cadenceDays: 7, requeued: [child])
        )
        #expect(result.upNext == [child])
        #expect(result.met.isEmpty)
    }

    @Test("By need: booked today, then never met, then longest wait, then roster order")
    func ordersByNeed() {
        let bookedToday = UUID(), never = UUID(), longest = UUID(), shorter = UUID(), tieA = UUID(), tieB = UUID()
        let result = arrange([tieA, shorter, tieB, longest, never, bookedToday], [
            bookedToday: MeetingQueueSignals(lastMet: daysAgo(8), scheduled: calendar.startOfDay(for: now)),
            longest: MeetingQueueSignals(lastMet: daysAgo(30)),
            shorter: MeetingQueueSignals(lastMet: daysAgo(10)),
            tieA: MeetingQueueSignals(lastMet: daysAgo(9)),
            tieB: MeetingQueueSignals(lastMet: daysAgo(9))
        ])
        #expect(result.upNext == [bookedToday, never, longest, shorter, tieA, tieB])
    }

    @Test("A booking for a later day doesn't jump the queue")
    func futureBookingSortsByWait() {
        let bookedLater = UUID(), waiting = UUID()
        let inThreeDays = calendar.date(byAdding: .day, value: 3, to: now)
        let result = arrange([bookedLater, waiting], [
            bookedLater: MeetingQueueSignals(lastMet: daysAgo(8), scheduled: inThreeDays),
            waiting: MeetingQueueSignals(lastMet: daysAgo(20))
        ])
        #expect(result.upNext == [waiting, bookedLater])
    }

    @Test("Custom order keeps the dragged order and appends anyone not in it")
    func customOrder() {
        let first = UUID(), second = UUID(), unplaced = UUID(), met = UUID()
        let result = arrange(
            [unplaced, second, first, met],
            [met: MeetingQueueSignals(lastMet: daysAgo(1))],
            rules: MeetingQueueRules(cadenceDays: 7, order: .custom, customOrder: [first, met, second])
        )
        #expect(result.upNext == [first, second, unplaced])
        #expect(result.met == [met])
    }

    // MARK: - Stuck work

    @Test("Work set resting isn't stuck in the queue or the next meeting; this meeting's card stays")
    @MainActor
    func restingWorkIsNotStuck() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let child = UUID()
        let today = Date()
        let monthAgo = try #require(AppCalendar.shared.date(byAdding: .day, value: -30, to: today))
        let startOfToday = AppCalendar.startOfDay(today)
        let nextWeek = try #require(AppCalendar.shared.date(byAdding: .day, value: 7, to: startOfToday))
        let resting = CoreDataTestHelpers.seedWorkModel(in: context, title: "Resting", studentID: child)
        resting.createdAt = monthAgo
        resting.restingUntil = nextWeek
        let stuck = CoreDataTestHelpers.seedWorkModel(in: context, title: "Stuck", studentID: child)
        stuck.createdAt = monthAgo
        let woke = CoreDataTestHelpers.seedWorkModel(in: context, title: "Woke today", studentID: child)
        woke.createdAt = monthAgo
        woke.restingUntil = startOfToday
        #expect(CoreDataTestHelpers.save(context))

        let queue = MeetingQueueModel()
        queue.refreshIfNeeded(context: context, workOverdueDays: 14, now: today)
        #expect(queue.signals[child]?.stuckWork == 2)

        let work = [resting, stuck, woke]
        let nextMeeting = MeetingWorkSnapshotHelper.sessionWork(work, workOverdueDays: 14, reviewed: [], now: today)
        #expect(nextMeeting.stuck.map(\.title) == ["Stuck", "Woke today"])
        #expect(nextMeeting.open.map(\.title) == ["Resting"])

        let restedNow = try #require(resting.id)
        let thisMeeting = MeetingWorkSnapshotHelper.sessionWork(
            work, workOverdueDays: 14, reviewed: [restedNow], now: today
        )
        #expect(thisMeeting.stuck.map(\.title) == ["Resting", "Stuck", "Woke today"])
    }

    @Test("The queue's day moves at midnight even when no signal does, so its cutoffs redraw")
    @MainActor
    func dayTurnsOver() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let evening = try #require(AppCalendar.shared.date(bySettingHour: 23, minute: 30, second: 0, of: Date()))
        let morning = try #require(AppCalendar.shared.date(byAdding: .hour, value: 9, to: evening))

        let queue = MeetingQueueModel()
        queue.refreshIfNeeded(context: context, workOverdueDays: 14, now: evening)
        #expect(queue.day == AppCalendar.startOfDay(evening))
        let signals = queue.signals

        queue.refreshIfNeeded(context: context, workOverdueDays: 14, now: morning)
        #expect(queue.signals == signals)
        #expect(queue.day == AppCalendar.startOfDay(morning))
    }
}
