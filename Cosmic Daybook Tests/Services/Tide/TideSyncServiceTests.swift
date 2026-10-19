import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// When the sharing runs: one run at a time, a run in flight never cut
/// short, and changes made during a run picked up after it. Against a fake
/// Tide held mid-call, with the waits shortened.
@Suite("Tide sync service", .serialized)
@MainActor
struct TideSyncServiceTests {

    /// A service on an in-memory notebook and a fake Tide, its first run
    /// confirmed unless asked.
    final class Rig {
        let context: NSManagedObjectContext
        let tide = FakeTide()
        let defaults: UserDefaults
        private let suite = "TideSyncServiceTests-\(UUID().uuidString)"
        let service: TideSyncService

        init(confirmed: Bool = true) throws {
            context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
            defaults = try #require(UserDefaults(suiteName: suite))
            if confirmed {
                var state = TideSyncState()
                state.firstRunConfirmedAt = Date()
                state.save(to: defaults)
            }
            let address = try TideAddress.parse("http://localhost:4877/\(String(repeating: "ab", count: 20))/mcp").get()
            let timing = TideSyncService.Timing(
                start: .milliseconds(10), change: .milliseconds(40), settingsChange: .milliseconds(40),
                interval: .seconds(3600), intervalWhileAway: .seconds(3600), tolerance: .milliseconds(5)
            )
            let keeper = TideSyncService.AddressKeeper(load: { address }, save: { _ in }, delete: {})
            let tide = tide
            service = TideSyncService(
                defaults: defaults, policy: .live, timing: timing, keeper: keeper,
                shouldDefer: { false }, makeTransport: { _ in tide }
            )
            service.settings.isOn = true
        }

        deinit { UserDefaults().removePersistentDomain(forName: suite) }

        func start() {
            service.start(context: context, saveCoordinator: SaveCoordinator())
        }

        @discardableResult
        func todo(_ title: String) -> CDTodoItem {
            let todo = CDTodoItem(context: context)
            todo.title = title
            #expect(CoreDataTestHelpers.save(context))
            return todo
        }

        func calls(_ name: String) -> Int { tide.callNames.filter { $0 == name }.count }

        /// Waits, up to `timeout`, for `condition`.
        func eventually(_ timeout: Duration = .seconds(5), _ condition: () -> Bool) async -> Bool {
            let clock = ContinuousClock()
            let end = clock.now + timeout
            while clock.now < end {
                if condition() { return true }
                try? await Task.sleep(for: .milliseconds(10))
            }
            return condition()
        }
    }

    @Test("A change that replaces the scheduled wait doesn't cut short the run already in flight")
    func runInFlightIsNotCancelled() async throws {
        let rig = try Rig()
        let todo = rig.todo("Plan the field trip")
        let gate = TideTestGate()
        rig.tide.gate = gate
        rig.tide.holdTool = "add_action"
        rig.start()
        #expect(await rig.eventually { gate.arrivals == 1 }, "the launch run is held mid-send")

        rig.service.settings.destinationHeading = "This week"
        await rig.service.syncNow()
        gate.open()

        #expect(await rig.eventually { !rig.service.isSyncing && todo.tideLink != nil })
        #expect(rig.service.statusMessage == TideSyncMessages.upToDate)
        #expect(!rig.service.statusIsProblem)
        #expect(rig.tide.actions.filter { $0.text == "Plan the field trip" }.count == 1)
    }

    @Test("One run at a time: asking again during a run makes one more run after it, never two at once")
    func oneRunAtATime() async throws {
        let rig = try Rig()
        rig.todo("Plan the field trip")
        let gate = TideTestGate()
        rig.tide.gate = gate
        rig.tide.holdTool = "get_area"
        rig.start()
        #expect(await rig.eventually { gate.arrivals == 1 })

        await rig.service.syncNow()
        await rig.service.syncNow()
        #expect(gate.arrivals == 1, "the second run waits for the first")
        gate.open()

        #expect(await rig.eventually { !rig.service.isSyncing && rig.calls("get_area") == 2 })
        try await Task.sleep(for: .milliseconds(100))
        #expect(rig.calls("get_area") == 2, "one follow-up for both presses")
        #expect(rig.calls("add_action") == 1)
    }

    @Test("Link and Start pressed during a run links once that run ends")
    func confirmingDuringARun() async throws {
        let rig = try Rig(confirmed: false)
        rig.tide.add("Order pin maps", in: FakeTide.roomSetup, heading: nil)
        let match = rig.todo("Order more pin maps")
        rig.start()
        #expect(await rig.eventually { rig.service.proposal != nil && !rig.service.isSyncing })
        let matches = try #require(rig.service.proposal?.matches)

        let gate = TideTestGate()
        rig.tide.gate = gate
        rig.tide.holdTool = "get_area"
        Task { await rig.service.syncNow() }
        #expect(await rig.eventually { gate.arrivals == 1 })
        await rig.service.confirmFirstRun(matches)
        #expect(match.tideLink == nil, "not linked while the other run is in flight")
        gate.open()

        #expect(await rig.eventually { !rig.service.isSyncing && match.tideLink != nil })
        #expect(rig.service.proposal == nil)
        #expect(rig.service.statusMessage == TideSyncMessages.upToDate)
    }

    @Test("A to-do added during a run goes across in a run after it")
    func editDuringARunSchedulesAnother() async throws {
        let rig = try Rig()
        rig.todo("Plan the field trip")
        let gate = TideTestGate()
        rig.tide.gate = gate
        rig.tide.holdTool = "add_action"
        rig.start()
        #expect(await rig.eventually { gate.arrivals == 1 }, "held after the run read the notebook")

        let added = rig.todo("Email the art teacher")
        gate.open()

        #expect(await rig.eventually { added.tideLink != nil })
        #expect(rig.calls("get_area") == 2)
    }

    @Test("The sync's own changes don't start another run")
    func ownChangesDontRepeat() async throws {
        let rig = try Rig()
        rig.tide.add("Label the shelves", in: FakeTide.roomSetup, heading: nil)
        rig.todo("Plan the field trip")
        rig.start()
        #expect(await rig.eventually {
            !rig.service.isSyncing && rig.calls("get_area") == 1 && rig.calls("update_action") == 1
        })

        try await Task.sleep(for: .milliseconds(200))
        #expect(rig.calls("get_area") == 1)
    }
}
