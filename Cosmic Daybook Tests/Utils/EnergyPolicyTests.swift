import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Discretionary maintenance stands down when the device is thermally stressed
// (`.serious` and above) or the user has turned on Low Power Mode. The rule
// itself is one boolean, so most of what is worth pinning is the behaviour at
// the call sites: they must pause or defer, never abandon the work outright,
// and they must never gate anything the guide asked for.
@MainActor
@Suite("Energy policy")
struct EnergyPolicyTests {

    private static func policy(
        _ thermalState: ProcessInfo.ThermalState,
        lowPower: Bool = false
    ) -> EnergyPolicy {
        EnergyPolicy(thermalState: thermalState, isLowPowerMode: lowPower)
    }

    /// Spins until `condition` holds, so a test never waits the full timeout on
    /// a passing run. The gated call sites all finish in milliseconds here.
    private func waitUntil(
        timeout: Duration = .seconds(30),
        _ condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    // MARK: - The rule

    @Test("A cool device on mains power runs maintenance")
    func nominalRuns() {
        #expect(Self.policy(.nominal).shouldDeferMaintenance == false)
        #expect(Self.policy(.fair).shouldDeferMaintenance == false)
    }

    @Test("Serious and critical thermal states defer maintenance")
    func hotDefers() {
        #expect(Self.policy(.serious).shouldDeferMaintenance)
        #expect(Self.policy(.critical).shouldDeferMaintenance)
    }

    @Test("Low Power Mode defers maintenance at every thermal state")
    func lowPowerDefers() {
        let states: [ProcessInfo.ThermalState] = [.nominal, .fair, .serious, .critical]
        for state in states {
            #expect(Self.policy(state, lowPower: true).shouldDeferMaintenance,
                    "Low Power Mode should defer at \(state.energyPolicyName)")
        }
    }

    @Test("The pure rule agrees with the instance for every input combination")
    func pureRuleMatchesInstance() {
        let states: [ProcessInfo.ThermalState] = [.nominal, .fair, .serious, .critical]
        for state in states {
            for lowPower in [false, true] {
                let inputs = EnergyPolicy.Inputs(thermalState: state, isLowPowerModeEnabled: lowPower)
                let expected = lowPower || state == .serious || state == .critical
                #expect(EnergyPolicy.shouldDefer(inputs) == expected)
                #expect(Self.policy(state, lowPower: lowPower).shouldDeferMaintenance == expected)
            }
        }
    }

    @Test("A pinned policy reports the inputs it was built with")
    func inputsAreReadable() {
        let policy = Self.policy(.serious, lowPower: true)
        #expect(policy.inputs.thermalState == .serious)
        #expect(policy.inputs.isLowPowerModeEnabled)
    }

    // MARK: - Deduplication debounce

    @Test("A cool device dedups on the first debounce tick")
    func deduplicationRunsWhenCool() async {
        let coordinator = DeduplicationCoordinator(debounceInterval: .milliseconds(1))
        coordinator.requestDeduplication(policy: Self.policy(.nominal))

        #expect(await waitUntil { coordinator.runAttemptCount == 1 })
        #expect(coordinator.energyDeferralCount == 0)
    }

    @Test("A hot device waits instead of dedupping")
    func deduplicationWaitsWhenHot() async {
        let policy = Self.policy(.critical)
        let coordinator = DeduplicationCoordinator(debounceInterval: .milliseconds(1))
        coordinator.requestDeduplication(policy: policy)

        #expect(await waitUntil { policy.waitingTaskCount == 1 })
        #expect(coordinator.energyDeferralCount == 1)
        #expect(coordinator.runAttemptCount == 0)
    }

    @Test("A permanently hot device never dedups; it runs once the device cools")
    func deduplicationNeverRunsHotThenRunsWhenCool() async {
        let policy = Self.policy(.serious, lowPower: true)
        let coordinator = DeduplicationCoordinator(debounceInterval: .milliseconds(1))
        coordinator.requestDeduplication(policy: policy)
        #expect(await waitUntil { policy.waitingTaskCount == 1 })

        // Many debounce intervals later it is still waiting, not running.
        for _ in 0..<50 { await Task.yield() }
        #expect(coordinator.runAttemptCount == 0)
        #expect(policy.waitingTaskCount == 1)

        // Cooling off alone does not clear Low Power Mode.
        policy.simulate(.init(thermalState: .nominal, isLowPowerModeEnabled: true))
        for _ in 0..<50 { await Task.yield() }
        #expect(coordinator.runAttemptCount == 0)

        policy.simulate(.init(thermalState: .nominal, isLowPowerModeEnabled: false))
        #expect(await waitUntil { coordinator.runAttemptCount == 1 })
        #expect(policy.waitingTaskCount == 0)
    }

    @Test("A fresh request starts the deferral count over")
    func deduplicationResetsCountOnNewRequest() async {
        let hot = Self.policy(.critical)
        let coordinator = DeduplicationCoordinator(debounceInterval: .milliseconds(1))
        coordinator.requestDeduplication(policy: hot)
        #expect(await waitUntil { coordinator.energyDeferralCount > 0 })

        coordinator.requestDeduplication(policy: Self.policy(.nominal))
        #expect(coordinator.energyDeferralCount == 0)
        #expect(await waitUntil { coordinator.runAttemptCount >= 1 })
        // The superseded wait was cancelled, not left suspended.
        #expect(await waitUntil { hot.waitingTaskCount == 0 })
    }

    // MARK: - Album indexing

    @Test("Album indexing does not pause on a cool device")
    func albumIndexingRunsWhenCool() async {
        let pauses = await AlbumLibrary.shared.pauseIndexingWhileDeferred(policy: Self.policy(.fair))
        #expect(pauses == 0)
    }

    @Test("Album indexing waits while hot for as long as it lasts, then continues when cool")
    func albumIndexingPausesWhenHot() async {
        let policy = Self.policy(.critical)
        let pause = Task { await AlbumLibrary.shared.pauseIndexingWhileDeferred(policy: policy) }
        #expect(await waitUntil { policy.waitingTaskCount == 1 })

        policy.simulate(.init(thermalState: .fair, isLowPowerModeEnabled: false))
        #expect(await pause.value == 1)
        #expect(policy.waitingTaskCount == 0)
    }

    @Test("A cancelled indexing pass stops waiting for the device to cool")
    func albumIndexingWaitEndsOnCancel() async {
        let policy = Self.policy(.critical)
        let pause = Task { await AlbumLibrary.shared.pauseIndexingWhileDeferred(policy: policy) }
        #expect(await waitUntil { policy.waitingTaskCount == 1 })

        pause.cancel()
        _ = await pause.value
        #expect(await waitUntil { policy.waitingTaskCount == 0 })
        #expect(policy.shouldDeferMaintenance)
    }

    // MARK: - Zone repair

    @Test("A zone repair turned away by a hot device is retried once it cools")
    func zoneRepairRetriesWhenCool() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let policy = Self.policy(.critical)
        let repair = SharedStoreZoneRepair.shared
        let alreadyWaiting = repair.hasDeferredRetry

        await SharedStoreZoneRepair.runIfNeeded(coreDataStack: stack, policy: policy)
        // Not dropped: a retry is parked on the policy (unless the circuit
        // breaker was open on this machine, when nothing auto-runs at all).
        guard !SharedStoreZoneRepair.isCircuitBreakerOpen, !alreadyWaiting else { return }
        #expect(repair.hasDeferredRetry)
        // The parked task reaches the policy on its first turn.
        #expect(await waitUntil { policy.waitingTaskCount == 1 })
        #expect(repair.hasDeferredRetry)

        policy.simulate(.init(thermalState: .nominal, isLowPowerModeEnabled: false))
        #expect(await waitUntil { !repair.hasDeferredRetry })
        #expect(policy.waitingTaskCount == 0)
    }

    // MARK: - Scheduled backup

    @Test("A hot device defers the scheduled backup by one interval")
    func scheduledBackupDefersWhenHot() async throws {
        let clockKey = "AutoBackup.lastScheduledDate"
        let savedClock = UserDefaults.standard.object(forKey: clockKey)
        defer {
            if let savedClock {
                UserDefaults.standard.set(savedClock, forKey: clockKey)
            } else {
                UserDefaults.standard.removeObject(forKey: clockKey)
            }
        }

        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let manager = AutoBackupManager(
            coordinator: BackupCoordinator(
                backupService: BackupService(),
                transactionManager: BackupTransactionManager(),
                appRouter: AppRouter()
            )
        )
        // The only way to hand the manager a context; the loop it would start is
        // stopped immediately so this test never writes a real backup file.
        manager.startScheduledBackups(viewContext: stack.viewContext)
        manager.stopScheduledBackups()

        let before = Date()
        await manager.performScheduledBackup(policy: Self.policy(.serious))

        // Nothing was written…
        #expect(manager.lastBackupResult == nil)
        #expect(manager.lastBackupEvent == nil)
        // …but the schedule clock moved, so the next attempt is one interval out
        // rather than a hot retry loop.
        let advanced = try #require(manager.lastScheduledBackupDate)
        #expect(advanced >= before)
    }
}
