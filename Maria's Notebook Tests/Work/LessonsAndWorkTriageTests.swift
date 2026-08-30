import Foundation
import Testing
@testable import Maria_s_Notebook

/// Boundary tests for `LessonsAndWorkTriage`, the single rule behind the
/// Attention / Scheduled / To Schedule lists.
///
/// Every case pins an explicit "today" (Wednesday 10 June 2026) and feeds the
/// pure value inputs, so nothing here depends on the clock, the school
/// calendar, or Core Data.
@Suite("Lessons & Work Triage")
struct LessonsAndWorkTriageTests {

    // MARK: - Fixtures

    private func day(_ year: Int, _ month: Int, _ dayOfMonth: Int) -> Date {
        let components = DateComponents(year: year, month: month, day: dayOfMonth)
        return AppCalendar.startOfDay(AppCalendar.shared.date(from: components)!)
    }

    /// Wednesday 10 June 2026 — the reference "now" for every case below.
    private var today: Date { day(2026, 6, 10) }
    private var yesterday: Date { day(2026, 6, 9) }
    private var tomorrow: Date { day(2026, 6, 11) }
    private var nextWeek: Date { day(2026, 6, 17) }

    /// `today` with a wall-clock time on it, to prove the rule compares days
    /// rather than instants.
    private var thisAfternoon: Date {
        AppCalendar.shared.date(byAdding: .hour, value: 15, to: today)!
    }

    private func work(
        _ status: WorkStatus = .active,
        dueAt: Date? = nil,
        restingUntil: Date? = nil,
        checkIns: [Date] = [],
        staleDays: Int = 0
    ) -> WorkTriageInput {
        WorkTriageInput(
            status: status,
            dueAt: dueAt,
            restingUntil: restingUntil,
            scheduledCheckInDates: checkIns,
            schoolDaysSinceLastTouch: staleDays
        )
    }

    private func bucket(_ input: WorkTriageInput) -> TriageBucket {
        LessonsAndWorkTriage.bucket(for: input, asOf: today)
    }

    // MARK: - Work: the four ways it asks for the guide

    @Test("Work in review is waiting on the guide")
    func reviewNeedsAttention() {
        #expect(bucket(work(.review)) == .attention)
        // Even with a future date on it — the guide still owes it a decision.
        #expect(bucket(work(.review, dueAt: nextWeek)) == .attention)
    }

    @Test("A due date that has arrived or passed asks for the guide")
    func dueDateBoundary() {
        #expect(bucket(work(dueAt: yesterday)) == .attention)
        #expect(bucket(work(dueAt: today)) == .attention)
        #expect(bucket(work(dueAt: tomorrow)) == .scheduled)
    }

    @Test("Due today is compared by day, not by instant")
    func dueTodayIgnoresTimeOfDay() {
        // A due date stamped this afternoon is still due today, even when the
        // rule runs at midnight.
        #expect(bucket(work(dueAt: thisAfternoon)) == .attention)
    }

    @Test("A check-in whose day has come asks for the guide")
    func checkInBoundary() {
        #expect(bucket(work(checkIns: [yesterday])) == .attention)
        #expect(bucket(work(checkIns: [today])) == .attention)
        #expect(bucket(work(checkIns: [tomorrow])) == .scheduled)
    }

    @Test("The earliest check-in decides, not the latest")
    func earliestCheckInWins() {
        #expect(bucket(work(checkIns: [nextWeek, today])) == .attention)
        #expect(bucket(work(checkIns: [tomorrow, nextWeek])) == .scheduled)
    }

    @Test("Silence for ten school days asks for the guide")
    func staleBoundary() {
        #expect(bucket(work(staleDays: 9)) == .toSchedule)
        #expect(bucket(work(staleDays: 10)) == .attention)
        #expect(bucket(work(staleDays: 40)) == .attention)
    }

    @Test("One stale threshold drives both the badge colour and the Attention list")
    func staleThresholdIsShared() {
        // These were 9 and 10 once, so a card could look stale without ever
        // being asked for. Pinned so they cannot drift apart again.
        #expect(LessonsAndWorkTriage.staleSchoolDays == AgingPolicy.staleDays)
        #expect(AgingPolicy.staleDays == 10)
    }

    @Test("Stale work with a future date is still stale")
    func staleBeatsFutureDate() {
        // The regression this rule replaces: the old badge returned false as
        // soon as a recent note existed and never reached the age check.
        #expect(bucket(work(dueAt: nextWeek, staleDays: 12)) == .attention)
        #expect(bucket(work(checkIns: [nextWeek], staleDays: 12)) == .attention)
    }

    // MARK: - Work: resting

    @Test("Work deliberately set aside is planned, not neglected")
    func restingIsScheduled() {
        #expect(bucket(work(restingUntil: tomorrow)) == .scheduled)
        // Resting outranks every reason to nag, matching WorkAgingPolicy.
        #expect(bucket(work(.review, restingUntil: nextWeek)) == .scheduled)
        #expect(bucket(work(dueAt: yesterday, restingUntil: nextWeek)) == .scheduled)
        #expect(bucket(work(restingUntil: nextWeek, checkIns: [yesterday])) == .scheduled)
        #expect(bucket(work(restingUntil: nextWeek, staleDays: 40)) == .scheduled)
    }

    @Test("Rest expires the day it names")
    func restingExpires() {
        // `restingUntil == today` means the rest is over this morning.
        #expect(bucket(work(dueAt: yesterday, restingUntil: today)) == .attention)
        #expect(bucket(work(dueAt: yesterday, restingUntil: yesterday)) == .attention)
    }

    // MARK: - Work: the other buckets

    @Test("Completed work leaves the workspace")
    func completeIsDone() {
        #expect(bucket(work(.complete)) == .done)
        // Completion outranks everything, including a stale overdue date.
        #expect(bucket(work(.complete, dueAt: yesterday, staleDays: 40)) == .done)
    }

    @Test("Open work with no date of any kind has to be scheduled")
    func datelessWorkNeedsPlanning() {
        #expect(bucket(work()) == .toSchedule)
    }

    @Test("A future date of either kind counts as scheduled")
    func futureDatesAreScheduled() {
        #expect(bucket(work(dueAt: tomorrow)) == .scheduled)
        #expect(bucket(work(checkIns: [nextWeek])) == .scheduled)
    }

    // MARK: - Presentations

    @Test("A given presentation with an open follow-up is waiting on the guide")
    func openFollowUpNeedsAttention() {
        let input = PresentationTriageInput(state: .presented, hasUnresolvedFollowUp: true)
        #expect(LessonsAndWorkTriage.bucket(for: input) == .attention)
    }

    @Test("A given presentation with nothing outstanding is history")
    func resolvedPresentationIsDone() {
        let input = PresentationTriageInput(state: .presented, hasUnresolvedFollowUp: false)
        #expect(LessonsAndWorkTriage.bucket(for: input) == .done)
        // The day it was scheduled for does not bring it back.
        let dated = PresentationTriageInput(state: .presented, scheduledFor: yesterday)
        #expect(LessonsAndWorkTriage.bucket(for: dated) == .done)
    }

    @Test("A presentation with a day is scheduled; without one it has to be scheduled")
    func presentationDayDecides() {
        let planned = PresentationTriageInput(state: .scheduled, scheduledFor: tomorrow)
        #expect(LessonsAndWorkTriage.bucket(for: planned) == .scheduled)

        let draft = PresentationTriageInput(state: .draft)
        #expect(LessonsAndWorkTriage.bucket(for: draft) == .toSchedule)
    }

    @Test("The date outranks a stale state after a merge")
    func presentationStateMismatch() {
        // A draft that was handed a day is scheduled…
        let datedDraft = PresentationTriageInput(state: .draft, scheduledFor: tomorrow)
        #expect(LessonsAndWorkTriage.bucket(for: datedDraft) == .scheduled)

        // …and a row marked scheduled that carries no day still needs planning.
        let undatedScheduled = PresentationTriageInput(state: .scheduled)
        #expect(LessonsAndWorkTriage.bucket(for: undatedScheduled) == .toSchedule)
    }

    @Test("A presentation whose day has passed keeps its day, for now")
    func missedPresentationStaysScheduled() {
        // Documents today's behaviour deliberately: the calendar keeps showing
        // it, and "missed" is PresentationsMissWindow's job. Promoting these to
        // .attention is a behaviour change, not part of adopting the service.
        let missed = PresentationTriageInput(state: .scheduled, scheduledFor: yesterday)
        #expect(LessonsAndWorkTriage.bucket(for: missed) == .scheduled)
    }

    // MARK: - The partition itself

    @Test("Every open record lands in exactly one workspace list")
    func bucketsPartitionOpenRecords() {
        let allWork: [WorkTriageInput] = [
            work(), work(.review), work(dueAt: yesterday), work(dueAt: tomorrow),
            work(checkIns: [today]), work(checkIns: [nextWeek]),
            work(restingUntil: nextWeek), work(staleDays: 12)
        ]
        for input in allWork {
            let placed = bucket(input)
            #expect(placed != .done)
            #expect(TriageBucket.workspaceCases.contains(placed))
        }

        let allPresentations: [PresentationTriageInput] = [
            PresentationTriageInput(state: .draft),
            PresentationTriageInput(state: .scheduled, scheduledFor: tomorrow),
            PresentationTriageInput(state: .presented, hasUnresolvedFollowUp: true)
        ]
        for input in allPresentations {
            #expect(TriageBucket.workspaceCases.contains(LessonsAndWorkTriage.bucket(for: input)))
        }
    }

    @Test("The workspace shows three lists and history is not one of them")
    func workspaceCasesExcludeDone() {
        #expect(TriageBucket.workspaceCases == [.attention, .scheduled, .toSchedule])
        #expect(!TriageBucket.workspaceCases.contains(.done))
    }

    @Test("needsAttention agrees with the bucket it is derived from")
    func needsAttentionMatchesBucket() {
        for input in [work(), work(.review), work(dueAt: yesterday), work(restingUntil: nextWeek)] {
            let expected = LessonsAndWorkTriage.bucket(for: input, asOf: today) == .attention
            #expect(LessonsAndWorkTriage.needsAttention(input, asOf: today) == expected)
        }

        let open = PresentationTriageInput(state: .presented, hasUnresolvedFollowUp: true)
        #expect(LessonsAndWorkTriage.needsAttention(open))
        #expect(!LessonsAndWorkTriage.needsAttention(PresentationTriageInput(state: .draft)))
    }
}
