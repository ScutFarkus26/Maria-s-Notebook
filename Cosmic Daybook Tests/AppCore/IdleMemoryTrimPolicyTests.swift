import Testing
@testable import CosmicDaybook

// MARK: - When the Mac trims for being idle
//
// The Mac app frees the album library's rebuildable caches once it has been
// inactive (another app frontmost) for about ten minutes, once per inactive
// spell, and as its last main window closes. `IdleMemoryTrimController`
// sleeps until `trimDeadline` and asks `countdownElapsed`; these tests drive
// the policy with explicit instants, so the timing is exact and nothing sleeps.
// (`countdownElapsed` is mutating, so each result is bound before `#expect`.)

@Suite("Idle memory trim policy")
struct IdleMemoryTrimPolicyTests {
    private static let interval: Duration = .seconds(600)
    private static let start = ContinuousClock.now

    private static func at(_ seconds: Int) -> ContinuousClock.Instant {
        start.advanced(by: .seconds(seconds))
    }

    private static func policy() -> IdleMemoryTrimPolicy {
        IdleMemoryTrimPolicy(inactiveInterval: interval)
    }

    @Test("The default interval is ten minutes")
    func defaultIsTenMinutes() {
        #expect(IdleMemoryTrimPolicy.defaultInactiveInterval == .seconds(600))
    }

    @Test("An active app has no countdown and never trims")
    func activeNeverTrims() {
        var policy = Self.policy()
        #expect(policy.trimDeadline == nil)
        let trimmed = policy.countdownElapsed(at: Self.at(100_000))
        #expect(!trimmed)
    }

    @Test("Resigning active arms a trim one full interval later, not before")
    func resignArms() {
        var policy = Self.policy()
        policy.appResignedActive(at: Self.at(100))
        #expect(policy.trimDeadline == Self.at(700))
        let early = policy.countdownElapsed(at: Self.at(699))
        #expect(!early, "an early wake does not trim")
        #expect(policy.trimDeadline == Self.at(700), "and leaves the deadline where it was")
        let onTime = policy.countdownElapsed(at: Self.at(700))
        #expect(onTime)
    }

    @Test("Becoming active cancels the countdown; a stale wake does not trim")
    func becomeActiveCancels() {
        var policy = Self.policy()
        policy.appResignedActive(at: Self.at(100))
        policy.appBecameActive()
        #expect(policy.trimDeadline == nil)
        let atOldDeadline = policy.countdownElapsed(at: Self.at(700))
        let muchLater = policy.countdownElapsed(at: Self.at(5_000))
        #expect(!atOldDeadline)
        #expect(!muchLater)
    }

    @Test("Resigning again starts a full new interval, and the old wake is stale")
    func resignAgainRestartsInFull() {
        var policy = Self.policy()
        policy.appResignedActive(at: Self.at(100))
        policy.appBecameActive()
        policy.appResignedActive(at: Self.at(500))
        #expect(policy.trimDeadline == Self.at(1_100))
        let staleWake = policy.countdownElapsed(at: Self.at(700))
        #expect(!staleWake, "the first spell's countdown was cancelled")
        let early = policy.countdownElapsed(at: Self.at(1_099))
        #expect(!early)
        let onTime = policy.countdownElapsed(at: Self.at(1_100))
        #expect(onTime)
    }

    @Test("A repeated resign keeps the original start, so it never postpones the trim")
    func repeatedResignKeepsDeadline() {
        var policy = Self.policy()
        policy.appResignedActive(at: Self.at(100))
        policy.appResignedActive(at: Self.at(300))
        policy.appResignedActive(at: Self.at(650))
        #expect(policy.trimDeadline == Self.at(700))
        let onTime = policy.countdownElapsed(at: Self.at(700))
        #expect(onTime)
    }

    @Test("One trim per inactive spell; the next spell after an activation trims again")
    func oneTrimPerSpell() {
        var policy = Self.policy()
        policy.appResignedActive(at: Self.at(100))
        let first = policy.countdownElapsed(at: Self.at(700))
        #expect(first)
        #expect(policy.trimDeadline == nil)
        let sameSpell = policy.countdownElapsed(at: Self.at(1_300))
        #expect(!sameSpell, "still the same inactive spell")
        policy.appResignedActive(at: Self.at(1_400))
        #expect(policy.trimDeadline == nil, "a repeated resign does not re-arm a spent spell")
        policy.appBecameActive()
        policy.appResignedActive(at: Self.at(2_000))
        #expect(policy.trimDeadline == Self.at(2_600))
        let nextSpell = policy.countdownElapsed(at: Self.at(2_600))
        #expect(nextSpell)
    }

    @Test("Closing the last main window trims; closing one of two, or another window, does not")
    func lastMainWindowClose() {
        #expect(IdleMemoryTrimPolicy.shouldTrimOnWindowClose(closingMainWindow: true, otherOpenMainWindows: 0))
        #expect(!IdleMemoryTrimPolicy.shouldTrimOnWindowClose(closingMainWindow: true, otherOpenMainWindows: 1))
        #expect(!IdleMemoryTrimPolicy.shouldTrimOnWindowClose(closingMainWindow: false, otherOpenMainWindows: 0))
    }
}
