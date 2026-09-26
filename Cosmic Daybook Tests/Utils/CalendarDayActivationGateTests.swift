import Foundation
import Testing
@testable import CosmicDaybook

/// The decision behind `onCalendarDayChange`'s scene-activation path: an
/// activation reruns the action only when the day, the school calendar or the
/// counter epoch moved since the view last caught up.
@Suite("Calendar-day activation gate")
@MainActor
struct CalendarDayActivationGateTests {

    private typealias Stamp = CalendarDayActivationGate.Stamp

    private let today = AppCalendar.startOfDay(Date(timeIntervalSinceReferenceDate: 812_000_000))
    private var tomorrow: Date { AppCalendar.addingDays(1, to: today) }

    /// A gate that last caught up with `today`, school-calendar version 4, no epoch.
    private func caughtUpToday() -> CalendarDayActivationGate {
        var gate = CalendarDayActivationGate()
        gate.record(Stamp(day: today, schoolDayVersion: 4, counterEpoch: nil))
        return gate
    }

    @Test("Same day, school calendar and epoch: activations do nothing")
    func sameStampIsNotDue() {
        var gate = caughtUpToday()
        let first = gate.activationIsDue(Stamp(day: today, schoolDayVersion: 4, counterEpoch: nil))
        let second = gate.activationIsDue(Stamp(day: today, schoolDayVersion: 4, counterEpoch: nil))
        #expect(first == false)
        #expect(second == false)
    }

    @Test("A new day is due once, then remembered")
    func newDayIsDueOnce() {
        var gate = caughtUpToday()
        let first = gate.activationIsDue(Stamp(day: tomorrow, schoolDayVersion: 4, counterEpoch: nil))
        let second = gate.activationIsDue(Stamp(day: tomorrow, schoolDayVersion: 4, counterEpoch: nil))
        #expect(first == true)
        #expect(second == false)
    }

    @Test("A school-calendar change is due on the same day")
    func schoolCalendarBumpIsDue() {
        var gate = caughtUpToday()
        let due = gate.activationIsDue(Stamp(day: today, schoolDayVersion: 5, counterEpoch: nil))
        #expect(due == true)
    }

    @Test("A counter-epoch change is due on the same day")
    func counterEpochChangeIsDue() {
        var gate = caughtUpToday()
        let due = gate.activationIsDue(Stamp(day: today, schoolDayVersion: 4, counterEpoch: today))
        #expect(due == true)
    }

    @Test("With nothing recorded, the first activation is due")
    func unrecordedIsDue() {
        var gate = CalendarDayActivationGate()
        let due = gate.activationIsDue(Stamp(day: today, schoolDayVersion: 4, counterEpoch: nil))
        #expect(due == true)
        #expect(gate.lastStamp == Stamp(day: today, schoolDayVersion: 4, counterEpoch: nil))
    }

    @Test("A day-change run caught up: the activation after it is not due")
    func recordAfterNotificationRun() {
        var gate = caughtUpToday()
        gate.record(Stamp(day: tomorrow, schoolDayVersion: 4, counterEpoch: nil))
        let due = gate.activationIsDue(Stamp(day: tomorrow, schoolDayVersion: 4, counterEpoch: nil))
        #expect(due == false)
    }

    @Test("The current stamp reads the day and the school-calendar version")
    func currentStampReadsItsInputs() {
        let now = Date()
        let before = Stamp.current(now: now)
        #expect(before.day == AppCalendar.startOfDay(now))

        // Other suites bump the version too; it only ever grows.
        SchoolDayDataVersion.bump()
        let after = Stamp.current(now: now)
        #expect(after.schoolDayVersion > before.schoolDayVersion)

        var gate = CalendarDayActivationGate()
        gate.record(before)
        let due = gate.activationIsDue(after)
        #expect(due == true)
    }
}
