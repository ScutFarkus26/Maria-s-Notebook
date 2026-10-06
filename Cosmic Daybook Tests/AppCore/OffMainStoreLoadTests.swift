import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Hunt of 2026-10-05, #19: the notebook's stores opened on the main thread in
// the App's init (the store lock, the pre-migration copy, the schema and key
// repairs, a migration), so nothing could be drawn until they had, and a slow
// open could outlast the time the system gives a launch. They now open off the
// main thread behind "Opening your notebook…", and everything that needs the
// stack awaits one shared load: the window, the App Intents (Siri's included,
// within an intent's 30 seconds), the background backup, the MCP-only launch.

@Suite("Opening the store off the main thread")
@MainActor
struct OffMainStoreLoadTests {

    // MARK: - One load for every caller

    @Test("Callers who ask while the load runs all wait for that one load")
    func concurrentCallersShareOneLoad() async {
        let gate = Gate()
        let runs = Counter()
        let load = SharedLaunchLoad<Int> {
            runs.count += 1
            await gate.wait()
            return 42
        }

        let first = Task { await load.value() }
        let second = Task { await load.value() }
        let third = Task { await load.value(waitingAtMost: .seconds(30)) }
        await yieldUntil { runs.count == 1 }
        await yield(times: 5)
        #expect(load.result == nil)

        gate.open()
        #expect(await first.value == 42)
        #expect(await second.value == 42)
        #expect(await third.value == 42)
        #expect(runs.count == 1)
        // A later caller gets the same result without another load.
        #expect(await load.value() == 42)
        #expect(runs.count == 1)
    }

    @Test("An intent stops waiting at its limit, and the load carries on for the next caller")
    func timeLimitedCallerGivesUpButLoadContinues() async {
        let gate = Gate()
        let runs = Counter()
        let load = SharedLaunchLoad<Int> {
            runs.count += 1
            await gate.wait()
            return 7
        }

        let early = await load.value(waitingAtMost: .milliseconds(50))
        #expect(early == nil)
        #expect(load.result == nil)

        gate.open()
        #expect(await load.value() == 7)
        #expect(load.result == 7)
        #expect(runs.count == 1)
    }

    @Test("A load that finishes within the limit reaches the waiting intent")
    func loadWithinLimitIsHandedOver() async {
        let load = SharedLaunchLoad<Int> { 9 }
        #expect(await load.value(waitingAtMost: .seconds(5)) == 9)
        // Once finished, even a zero limit gets it.
        #expect(await load.value(waitingAtMost: .zero) == 9)
    }

    // MARK: - What an intent is handed

    @Test("An intent gets the stack, a plain refusal while it's opening, and another when it couldn't open")
    func intentStackRefusesPlainly() throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        #expect(try AppBootstrapping.intentStack(stack, initError: nil) === stack)

        #expect(throws: NotebookUnavailableError.stillOpening) {
            try AppBootstrapping.intentStack(nil, initError: nil)
        }
        let failure = NSError(domain: NSCocoaErrorDomain, code: NSPersistentStoreIncompatibleVersionHashError)
        #expect(throws: NotebookUnavailableError.couldNotOpen) {
            try AppBootstrapping.intentStack(stack, initError: failure)
        }

        // What Siri and Shortcuts say: plain words, no codes.
        for error in [NotebookUnavailableError.stillOpening, .couldNotOpen] {
            let message = try #require(error.errorDescription)
            #expect(message.contains("your notebook"))
            let hasDigits = message.contains { $0.isNumber }
            #expect(!hasDigits)
        }
    }

    @Test("A Siri attendance command opens the class through the shared, awaited stack")
    func siriAttendanceAwaitsTheSharedStack() async throws {
        let stack = try await SiriHost.stack()
        #expect(stack === AppBootstrapping.getSharedCoreDataStack())
        let stores = stack.container.persistentStoreCoordinator.persistentStores
        #expect(!stores.isEmpty)
        #expect(stores.allSatisfy { $0.type == NSInMemoryStoreType })

        let session = try await SiriAttendance()
        #expect(session.context === stack.viewContext)
        // Siri's name lookups open the class the same way.
        _ = try await StudentEntityQuery().suggestedEntities()
    }

    // MARK: - The stores open off the main thread

    @Test("The stores open on a background thread and the main actor finishes the stack")
    func storesOpenOffMainAndFinishOnMain() async throws {
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OffMainStoreLoad-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storeURL = folder.appendingPathComponent("notebook.sqlite")

        let (opened, openedOnMain) = try await Self.openOffMain(storeURL: storeURL)
        #expect(!openedOnMain)
        #expect(!opened.isCloudKitActive)
        #expect(!opened.isAppNotebook)

        let stack = CoreDataStack(opened: opened)
        let context = stack.viewContext
        #expect((context.mergePolicy as? NSMergePolicy) === NSMergePolicy.mergeByPropertyObjectTrump)
        #expect(context.transactionAuthor == PersistentHistoryProcessor.transactionAuthor)
        #expect(context.undoManager == nil)
        #expect(CoreDataStack.cloudKitContainer(for: context) === stack.container)
        #expect(stack.historyProcessor == nil)
        #expect(stack.container.persistentStoreCoordinator.persistentStores.first?.url == storeURL)

        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = "Maya"
        student.lastName = "Stone"
        try context.save()
        #expect(context.safeFetch(CDFetchRequest(CDStudent.self)).count == 1)
    }

    @Test("While the stores open the window says so, with the main actor free to draw it")
    func loadingStateShowsWhileStoresOpen() async throws {
        let gate = Gate()
        let loaded = Counter()
        let loading = Task {
            await AppBootstrapping.loadSharedStack(
                create: {
                    await gate.wait()
                    return try CoreDataTestHelpers.makeInMemoryStack()
                },
                didLoad: { _ in loaded.count += 1 }
            )
        }
        await yieldUntil { AppBootstrapper.shared.state == .initializingContainer }
        // This test runs on the main actor: it got here while the load waits.
        #expect(AppBootstrapper.shared.state == .initializingContainer)
        #expect(loaded.count == 0)

        gate.open()
        let stack = await loading.value
        #expect(AppBootstrapper.shared.state == .idle)
        #expect(loaded.count == 1)
        #expect(!stack.container.persistentStoreCoordinator.persistentStores.isEmpty)
    }

    // MARK: - The app's objects

    @Test("The app's objects are built once, on the shared stack, for every caller")
    func openNotebookIsBuiltOnce() async {
        async let first = NotebookOpener.shared.open()
        async let second = NotebookOpener.shared.open()
        let (one, two) = await (first, second)
        #expect(one === two)
        #expect(NotebookOpener.shared.notebook === one)
        #expect(one.coreDataStack === AppBootstrapping.getSharedCoreDataStack())
        #expect(one.dependencies.coreDataStack === one.coreDataStack)
        #expect(one.classroomWorkspace.primaryStack === one.coreDataStack)
        #expect(one.saveCoordinator === one.dependencies.saveCoordinator)
    }

    // MARK: - Helpers

    @concurrent
    private static func openOffMain(storeURL: URL) async throws -> (CoreDataStack.OpenedStores, Bool) {
        let opened = try CoreDataStack.openStores(
            enableCloudKit: false,
            inMemory: false,
            preserveSplitStoreLayout: false,
            localStoreURL: storeURL,
            managedObjectModel: nil
        )
        return (opened, isMainThread())
    }

    nonisolated private static func isMainThread() -> Bool {
        Thread.isMainThread
    }

    /// Lets the main actor's other work run until `condition` holds (or a
    /// thousand turns pass, so a broken load fails the test, not the run).
    private func yieldUntil(_ condition: () -> Bool) async {
        var turns = 0
        while !condition(), turns < 1_000 {
            await Task.yield()
            turns += 1
        }
    }

    private func yield(times: Int) async {
        for _ in 0..<times {
            await Task.yield()
        }
    }
}

/// Holds a load until the test lets it go.
@MainActor
private final class Gate {
    private var waiting: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiting = $0 }
    }

    func open() {
        isOpen = true
        waiting?.resume()
        waiting = nil
    }
}

@MainActor
private final class Counter {
    var count = 0
}
