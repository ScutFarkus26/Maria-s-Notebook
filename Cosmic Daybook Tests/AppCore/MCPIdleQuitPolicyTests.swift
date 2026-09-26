import Testing
@testable import CosmicDaybook

// MARK: - When an MCP-only launch quits
//
// An MCP-only launch (the Claude bridge started the app) quits about ten
// minutes after the last Claude client disconnects — never while a client is
// connected or a window is open, and only after the whole interval has passed
// in quiet. `MCPIdleQuitController` sleeps until `quitDeadline` and asks
// `shouldQuit`; these tests drive the policy with explicit instants, so the
// timing is exact and nothing sleeps.

@Suite("MCP idle quit policy")
struct MCPIdleQuitPolicyTests {
    private static let interval: Duration = .seconds(600)
    private static let launch = ContinuousClock.now

    private static func at(_ seconds: Int) -> ContinuousClock.Instant {
        launch.advanced(by: .seconds(seconds))
    }

    private static func policy() -> MCPIdleQuitPolicy {
        MCPIdleQuitPolicy(idleInterval: interval, launchedAt: launch)
    }

    @Test("The default interval is ten minutes")
    func defaultIsTenMinutes() {
        #expect(MCPIdleQuitPolicy.defaultIdleInterval == .seconds(600))
    }

    @Test("A launch nobody connects to quits one interval after launch, not before")
    func unusedLaunchQuits() {
        let policy = Self.policy()
        #expect(policy.quitDeadline == Self.at(600))
        #expect(!policy.shouldQuit(at: Self.at(599)))
        #expect(policy.shouldQuit(at: Self.at(600)))
    }

    @Test("A connected client cancels the countdown for as long as it stays")
    func connectionCancels() {
        var policy = Self.policy()
        policy.connectionCountChanged(to: 1, at: Self.at(5))
        #expect(policy.quitDeadline == nil)
        #expect(!policy.shouldQuit(at: Self.at(10_000)))
    }

    @Test("The countdown restarts in full when the last client leaves")
    func lastDisconnectRearms() {
        var policy = Self.policy()
        policy.connectionCountChanged(to: 1, at: Self.at(5))
        policy.connectionCountChanged(to: 2, at: Self.at(60))
        policy.connectionCountChanged(to: 1, at: Self.at(300))
        #expect(policy.quitDeadline == nil, "one client is still connected")
        policy.connectionCountChanged(to: 0, at: Self.at(900))
        #expect(policy.quitDeadline == Self.at(1_500))
        #expect(!policy.shouldQuit(at: Self.at(1_499)))
        #expect(policy.shouldQuit(at: Self.at(1_500)))
    }

    @Test("A client that comes and goes inside the interval pushes the quit back a full interval")
    func briefConnectionPushesBack() {
        var policy = Self.policy()
        policy.connectionCountChanged(to: 1, at: Self.at(590))
        policy.connectionCountChanged(to: 0, at: Self.at(595))
        #expect(!policy.shouldQuit(at: Self.at(600)), "the launch countdown was cancelled")
        #expect(!policy.shouldQuit(at: Self.at(1_194)))
        #expect(policy.shouldQuit(at: Self.at(1_195)))
    }

    @Test("An open window keeps the app alive with no client; closing it re-arms")
    func windowsCancelAndRearm() {
        var policy = Self.policy()
        policy.windowCountChanged(to: 1, at: Self.at(100))   // a Dock click opened the main window
        #expect(policy.quitDeadline == nil)
        #expect(!policy.shouldQuit(at: Self.at(5_000)))
        policy.windowCountChanged(to: 2, at: Self.at(200))
        policy.windowCountChanged(to: 0, at: Self.at(3_000))  // the last one closed
        #expect(policy.quitDeadline == Self.at(3_600))
        #expect(policy.shouldQuit(at: Self.at(3_600)))
    }

    @Test("It quits only when both clients and windows are gone")
    func needsBothQuiet() {
        var policy = Self.policy()
        policy.connectionCountChanged(to: 1, at: Self.at(10))
        policy.windowCountChanged(to: 1, at: Self.at(20))
        policy.connectionCountChanged(to: 0, at: Self.at(30))
        #expect(policy.quitDeadline == nil, "a window is still open")
        policy.connectionCountChanged(to: 1, at: Self.at(40))
        policy.windowCountChanged(to: 0, at: Self.at(50))
        #expect(policy.quitDeadline == nil, "a client is still connected")
        policy.connectionCountChanged(to: 0, at: Self.at(70))
        #expect(policy.quitDeadline == Self.at(670))
    }

    @Test("A recount that finds nothing new leaves the countdown where it was")
    func spuriousRecountKeepsDeadline() {
        var policy = Self.policy()
        policy.connectionCountChanged(to: 1, at: Self.at(5))
        policy.connectionCountChanged(to: 0, at: Self.at(10))
        for second in stride(from: 20, through: 600, by: 20) {
            policy.windowCountChanged(to: 0, at: Self.at(second))
            policy.connectionCountChanged(to: 0, at: Self.at(second + 1))
        }
        #expect(policy.quitDeadline == Self.at(610))
        #expect(policy.shouldQuit(at: Self.at(610)))
    }

    @Test("Counts never go negative")
    func countsClampAtZero() {
        var policy = Self.policy()
        policy.connectionCountChanged(to: -1, at: Self.at(5))
        policy.windowCountChanged(to: -3, at: Self.at(6))
        #expect(policy.openConnections == 0)
        #expect(policy.openWindows == 0)
        #expect(policy.isQuiet)
        #expect(policy.quitDeadline == Self.at(600), "still quiet since launch")
    }
}
