import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// The power-source half of the energy policy: which profile a reading maps
// to, that deferred work waits for the device to cool (never gives up), and
// the iPad background-backup gap each profile buys.
@MainActor
@Suite("Energy profile")
struct EnergyProfileTests {

    private static let states: [ProcessInfo.ThermalState] = [.nominal, .fair, .serious, .critical]

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

    // MARK: - Profile rule

    @Test("Profile is constrained exactly when maintenance defers, else follows the power source")
    func profileRule() {
        for state in Self.states {
            for lowPower in [false, true] {
                for external in [false, true] {
                    let inputs = EnergyPolicy.Inputs(
                        thermalState: state, isLowPowerModeEnabled: lowPower, isOnExternalPower: external
                    )
                    let expected: EnergyPolicy.Profile = EnergyPolicy.shouldDefer(inputs)
                        ? .constrained
                        : (external ? .externalPower : .battery)
                    #expect(EnergyPolicy.profile(for: inputs) == expected)
                }
            }
        }
    }

    @Test("External power never overrides a hot device or Low Power Mode")
    func externalPowerStillDefersWhenHot() {
        #expect(EnergyPolicy(thermalState: .serious, isLowPowerMode: false, isOnExternalPower: true)
            .shouldDeferMaintenance)
        #expect(EnergyPolicy(thermalState: .nominal, isLowPowerMode: true, isOnExternalPower: true)
            .profile == .constrained)
    }

    // MARK: - Waiting for a cool device

    @Test("A cool device does not wait")
    func coolDeviceReturnsImmediately() async {
        let policy = EnergyPolicy(thermalState: .fair, isLowPowerMode: false)
        await policy.waitUntilMaintenanceAllowed()
        #expect(policy.waitingTaskCount == 0)
    }

    @Test("A hot device waits until it cools, however long that takes")
    func hotDeviceWaitsForCooling() async {
        let policy = EnergyPolicy(thermalState: .critical, isLowPowerMode: false)
        var finished = false
        let waiter = Task { @MainActor in
            await policy.waitUntilMaintenanceAllowed()
            finished = true
        }
        #expect(await waitUntil { policy.waitingTaskCount == 1 })

        // Still hot, just a different reading: keeps waiting.
        policy.simulate(.init(thermalState: .serious, isLowPowerModeEnabled: false))
        try? await Task.sleep(for: .milliseconds(50))
        #expect(finished == false)

        policy.simulate(.init(thermalState: .nominal, isLowPowerModeEnabled: false))
        await waiter.value
        #expect(finished)
        #expect(policy.waitingTaskCount == 0)
    }

    @Test("Cancelling a waiting task releases it")
    func cancellationReleasesWaiter() async {
        let policy = EnergyPolicy(thermalState: .critical, isLowPowerMode: true)
        let waiter = Task { @MainActor in
            await policy.waitUntilMaintenanceAllowed()
            return Task.isCancelled
        }
        #expect(await waitUntil { policy.waitingTaskCount == 1 })
        waiter.cancel()
        #expect(await waiter.value)
        #expect(await waitUntil { policy.waitingTaskCount == 0 })
    }

    // MARK: - iPad background backup gap

    @Test("Background backup gap: 15 min plugged in, 60 min on battery, none when constrained")
    func backgroundGapPerProfile() {
        #expect(AutoBackupManager.backgroundBackupMinimumGap(for: .externalPower) == 15 * 60)
        #expect(AutoBackupManager.backgroundBackupMinimumGap(for: .battery) == 60 * 60)
        #expect(AutoBackupManager.backgroundBackupMinimumGap(for: .constrained) == nil)
    }

    private func makeManager() throws -> (AutoBackupManager, NSManagedObjectContext) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let manager = AutoBackupManager(
            coordinator: BackupCoordinator(
                backupService: BackupService(),
                transactionManager: BackupTransactionManager(),
                appRouter: AppRouter()
            )
        )
        return (manager, stack.viewContext)
    }

    @Test("A hot device defers the background backup without collecting anything")
    func backgroundBackupDefersWhenHot() async throws {
        let (manager, context) = try makeManager()
        let outcome = await manager.performBackgroundBackup(
            viewContext: context,
            policy: EnergyPolicy(thermalState: .serious, isLowPowerMode: false, isOnExternalPower: true)
        )
        guard outcome != .disabled else { return } // auto-backup switched off on this host
        #expect(outcome == .deferredConstrained)
        #expect(manager.lastBackupResult == nil)
    }

    @Test("A background backup inside the gap is skipped without collecting anything")
    func backgroundBackupSkipsInsideGap() async throws {
        let key = UserDefaultsKeys.autoBackupLastBackgroundDate
        let saved = UserDefaults.standard.object(forKey: key)
        defer {
            if let saved { UserDefaults.standard.set(saved, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
        }
        let now = Date()
        UserDefaults.standard.set(now.addingTimeInterval(-10 * 60).timeIntervalSinceReferenceDate, forKey: key)

        let (manager, context) = try makeManager()
        let battery = EnergyPolicy(thermalState: .nominal, isLowPowerMode: false, isOnExternalPower: false)
        let outcome = await manager.performBackgroundBackup(viewContext: context, policy: battery, now: now)
        guard outcome != .disabled else { return }
        #expect(outcome == .tooSoon)
        #expect(manager.lastBackupResult == nil)
    }
}
