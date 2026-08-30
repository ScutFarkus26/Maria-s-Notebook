import Foundation
import Testing
@testable import Maria_s_Notebook

/// Covers the AM/PM balance gesture: which children count as doubled up, and
/// what the day looks like after the button that fixes it.
///
/// Two presentations sharing a child cannot share a half, and there are only
/// two halves — so this is graph two-colouring, and the interesting cases are
/// the ones it cannot colour. Those have to come back reported rather than
/// silently half-done.
@Suite("Balancing a day's halves")
struct DayBalanceTests {

    private func booking(_ period: DayPeriod, _ students: [UUID]) -> DayHalfBalancer.Booking {
        booking(UUID(), period, students)
    }

    /// The named-id overload, for the tests that assert where one card landed.
    private func booking(
        _ id: UUID,
        _ period: DayPeriod,
        _ students: [UUID]
    ) -> DayHalfBalancer.Booking {
        DayHalfBalancer.Booking(id: id, period: period, studentIDs: Set(students))
    }

    private func period(
        of id: UUID,
        in outcome: DayHalfBalancer.Outcome
    ) -> DayPeriod? {
        outcome.placements.first { $0.id == id }?.period
    }

    // MARK: - What counts as a clash

    @Test("A child is doubled up per half, not per day")
    func clashesAreScopedToTheHalf() {
        let tzofia = UUID()
        let morningTwice = [
            booking(.morning, [tzofia]),
            booking(.morning, [tzofia])
        ]
        #expect(DayHalfBalancer.clashes(in: morningTwice)[.morning] == [tzofia])

        // The same two lessons, one in each half, is the arrangement the whole
        // feature exists to produce — and is not a clash.
        let split = [
            booking(.morning, [tzofia]),
            booking(.afternoon, [tzofia])
        ]
        #expect(DayHalfBalancer.clashes(in: split).values.allSatisfy { $0.isEmpty })
    }

    @Test("A clash names only the half it happens in")
    func clashesAreKeyedByHalf() {
        let tzofia = UUID()
        let etty = UUID()
        let day = [
            booking(.morning, [tzofia, etty]),
            booking(.morning, [tzofia]),
            booking(.afternoon, [etty])
        ]
        let clashes = DayHalfBalancer.clashes(in: day)
        // Tzofia is doubled in the morning; Etty has one lesson in each half,
        // so her afternoon card must not draw the ring.
        #expect(clashes[.morning] == [tzofia])
        #expect(clashes[.afternoon, default: []].isEmpty)
    }

    // MARK: - Fixing what two halves can fix

    @Test("Two morning lessons sharing a child send the later one to the afternoon")
    func aPairSplitsAcrossTheSeam() {
        let tzofia = UUID()
        let first = UUID()
        let second = UUID()
        let outcome = DayHalfBalancer.balanced([
            booking(first, .morning, [tzofia]),
            booking(second, .morning, [tzofia])
        ])

        #expect(period(of: first, in: outcome) == .morning)
        #expect(period(of: second, in: outcome) == .afternoon)
        #expect(outcome.movedToAfternoon == [second])
        #expect(outcome.unresolvedStudentIDs.isEmpty)
    }

    @Test("A day that is already clean is left exactly alone")
    func nothingMovesWhenNothingClashes() {
        let tzofia = UUID()
        let etty = UUID()
        let day = [
            booking(.morning, [tzofia]),
            booking(.morning, [etty]),
            booking(.afternoon, [tzofia])
        ]
        let outcome = DayHalfBalancer.balanced(day)

        #expect(outcome.movedCount == 0)
        #expect(outcome.placements.map(\.period) == day.map(\.period))
    }

    @Test("Lessons that share nobody are never moved for tidiness")
    func unrelatedLessonsStayPut() {
        // Five unrelated lessons all in the morning is lopsided, and none of
        // the balancer's business — the guide put them there.
        let day = (0..<5).map { _ in booking(.morning, [UUID()]) }
        let outcome = DayHalfBalancer.balanced(day)

        #expect(outcome.movedCount == 0)
        #expect(outcome.placements.allSatisfy { $0.period == .morning })
    }

    @Test("A chain alternates rather than dragging the whole day across")
    func aChainAlternates() {
        // A shares a child with B, B with C, A and C share nobody — so C can
        // go back to the morning alongside A.
        let shared1 = UUID()
        let shared2 = UUID()
        let cardA = UUID()
        let cardB = UUID()
        let cardC = UUID()
        let outcome = DayHalfBalancer.balanced([
            booking(cardA, .morning, [shared1]),
            booking(cardB, .morning, [shared1, shared2]),
            booking(cardC, .morning, [shared2])
        ])

        #expect(period(of: cardA, in: outcome) == .morning)
        #expect(period(of: cardB, in: outcome) == .afternoon)
        #expect(period(of: cardC, in: outcome) == .morning)
        #expect(outcome.unresolvedStudentIDs.isEmpty)
        // Only the one card had to cross the seam.
        #expect(outcome.movedCount == 1)
    }

    @Test("Only the run that clashes is touched")
    func aClashDoesNotDisturbTheRestOfTheDay() {
        let tzofia = UUID()
        let bystander = UUID()
        let quiet = UUID()
        let clashingA = UUID()
        let clashingB = UUID()
        let outcome = DayHalfBalancer.balanced([
            booking(quiet, .morning, [bystander]),
            booking(clashingA, .morning, [tzofia]),
            booking(clashingB, .morning, [tzofia])
        ])

        #expect(period(of: quiet, in: outcome) == .morning)
        #expect(outcome.movedCount == 1)
    }

    // MARK: - Owning up to what two halves cannot fix

    @Test("A child on three lessons in one day cannot be separated")
    func threeLessonsForOneChildStayReported() {
        let tzofia = UUID()
        let outcome = DayHalfBalancer.balanced([
            booking(.morning, [tzofia]),
            booking(.morning, [tzofia]),
            booking(.morning, [tzofia])
        ])

        // Two halves and three lessons: someone doubles up whatever happens.
        #expect(outcome.unresolvedStudentIDs == [tzofia])
        // It still does what it can — two in one half and one in the other
        // beats three in a row.
        let halves = outcome.placements.map(\.period)
        #expect(halves.contains(.morning) && halves.contains(.afternoon))
    }

    @Test("An odd cycle is reported rather than half-fixed in silence")
    func anOddCycleIsReported() {
        // Three lessons, each sharing a different child with each other one.
        // No arrangement of two halves separates all three.
        let pairAB = UUID()
        let pairBC = UUID()
        let pairCA = UUID()
        let outcome = DayHalfBalancer.balanced([
            booking(.morning, [pairAB, pairCA]),
            booking(.morning, [pairAB, pairBC]),
            booking(.morning, [pairBC, pairCA])
        ])

        #expect(!outcome.unresolvedStudentIDs.isEmpty)
        // Exactly one pair is left sharing a half — the best two halves can do.
        #expect(outcome.unresolvedStudentIDs.count == 1)
    }

    @Test("An unfixable day is still improved as far as it goes")
    func anUnfixableDayIsStillImproved() {
        let pairAB = UUID()
        let pairBC = UUID()
        let pairCA = UUID()
        let bookings = [
            booking(.morning, [pairAB, pairCA]),
            booking(.morning, [pairAB, pairBC]),
            booking(.morning, [pairBC, pairCA])
        ]
        let before = DayHalfBalancer.clashes(in: bookings)
            .values.reduce(0) { $0 + $1.count }
        let after = DayHalfBalancer.balanced(bookings)
            .unresolvedStudentIDs.count

        #expect(before == 3)
        #expect(after < before)
    }

    // MARK: - Feeding the result back into the day

    @Test("A balanced day numbers into halves that read back clean")
    func balancedDaysSurviveNumbering() {
        let monday = AppCalendar.startOfDay(
            AppCalendar.shared.date(from: DateComponents(year: 2026, month: 6, day: 8))!
        )
        let tzofia = UUID()
        let etty = UUID()
        let bookings = [
            booking(.morning, [tzofia, etty]),
            booking(.morning, [tzofia]),
            booking(.morning, [etty])
        ]
        let outcome = DayHalfBalancer.balanced(bookings)
        let times = DayHalfPlanner.times(
            for: outcome.placements,
            on: monday,
            using: AppCalendar.shared,
            spacingSeconds: UIConstants.scheduleSpacingSeconds
        )

        // Read the halves back out of the written times, the way the column
        // does, and the day the guide sees has no clash left in it.
        let readBack = outcome.placements.map { placement in
            DayHalfBalancer.Booking(
                id: placement.id,
                period: DayPeriod(scheduledFor: times[placement.id]!),
                studentIDs: bookings.first { $0.id == placement.id }?.studentIDs ?? []
            )
        }
        #expect(DayHalfBalancer.clashes(in: readBack).values.allSatisfy { $0.isEmpty })
    }

    @Test("Every card in the day comes back, moved or not")
    func thePlacementsCoverTheWholeDay() {
        // `DayHalfPlanner.times` numbers a half by position in this list, so a
        // card left out would lose its place in the day.
        let tzofia = UUID()
        let bookings = [
            booking(.morning, [tzofia]),
            booking(.morning, [tzofia]),
            booking(.afternoon, [UUID()])
        ]
        let outcome = DayHalfBalancer.balanced(bookings)
        #expect(outcome.placements.map(\.id) == bookings.map(\.id))
    }

    @Test("Balancing twice changes nothing the second time")
    func balancingIsStable() {
        let tzofia = UUID()
        let etty = UUID()
        let bookings = [
            booking(.morning, [tzofia, etty]),
            booking(.morning, [tzofia]),
            booking(.morning, [etty]),
            booking(.afternoon, [UUID()])
        ]
        let once = DayHalfBalancer.balanced(bookings)
        let settled = once.placements.map { placement in
            DayHalfBalancer.Booking(
                id: placement.id,
                period: placement.period,
                studentIDs: bookings.first { $0.id == placement.id }?.studentIDs ?? []
            )
        }
        let twice = DayHalfBalancer.balanced(settled)

        #expect(twice.movedCount == 0)
        #expect(twice.placements == once.placements)
    }
}
