//
//  AppBootstrapping+SharedStack.swift
//  Cosmic Daybook
//
//  The one way to the notebook's Core Data stack. Its stores open off the
//  main thread (2026-10-05 hunt, #19), so everything that needs the stack
//  awaits it here: the window's startup, the App Intents (Siri's included),
//  the background backup and, on the Mac, an MCP-only launch's app delegate.
//

import CoreData
import Foundation
import OSLog

extension AppBootstrapping {

    /// The launch's one load of the notebook's stack.
    static let sharedStackLoad = SharedLaunchLoad<CoreDataStack> { await openSharedStack() }

    /// How long an App Intent waits for the stores to open: well inside the
    /// 30 seconds the system gives an intent (G8), leaving room for its own
    /// work and its reply.
    static let intentStackWait: Duration = .seconds(20)

    /// The notebook's Core Data stack.
    ///
    /// The stores open once, off the main thread, while the window says
    /// "Opening your notebook…"; a call made meanwhile waits for that same
    /// load, and every later one gets the same stack at once.
    /// `CosmicDaybookApp.init` starts the load (`startOpeningStores`), so the
    /// stores start opening at launch whether or not a window ever comes (a
    /// background intent brings up none, G8); a call before that starts it.
    ///
    /// When the stores can't be opened this is the in-memory stack behind
    /// the database-error screen (`initError` says so), as it always was.
    static func sharedCoreDataStack() async -> CoreDataStack {
        await sharedStackLoad.value()
    }

    /// The stack for an App Intent: `sharedCoreDataStack()`, waiting no
    /// longer than `intentStackWait`, and refusing when the stores couldn't
    /// be opened, so an intent never answers from (or saves into) the empty
    /// stack behind the database-error screen.
    static func sharedCoreDataStackForIntent() async throws -> CoreDataStack {
        let stack = await sharedStackLoad.value(waitingAtMost: intentStackWait)
        return try intentStack(stack, initError: initError)
    }

    /// What an intent is handed: the stack, unless it wasn't open in time
    /// (nil) or couldn't be opened (`initError`).
    static func intentStack(_ stack: CoreDataStack?, initError: Error?) throws -> CoreDataStack {
        guard let stack else {
            Logger.container.error("An intent stopped waiting for the notebook's stores to open")
            throw NotebookUnavailableError.stillOpening
        }
        guard initError == nil else { throw NotebookUnavailableError.couldNotOpen }
        return stack
    }

    /// The stack, for code that runs only once the notebook is open: what
    /// the window shows once it's ready, Settings, the MCP server (started
    /// after the stack), Ask AI. Anything that can run sooner awaits
    /// `sharedCoreDataStack()` instead.
    ///
    /// Hosted unit tests get an empty stack in memory. The macOS test host is
    /// the real app, in the real sandbox: opening the stores there opened the
    /// guide's live notebook, and launch surgery ran on it (2026-09-08).
    static func getSharedCoreDataStack() -> CoreDataStack {
        if let existing = _sharedCoreDataStack { return existing }
        if isRunningUnitTests {
            let stack = makeInMemoryStack()
            _sharedCoreDataStack = stack
            return stack
        }
        // Asked before the stores were open, by something that should have
        // awaited `sharedCoreDataStack()`. It can't wait here (the load
        // finishes on the main actor), so it gets an empty stand-in, which
        // is never kept as the notebook's.
        Logger.container.fault("The notebook's stack was asked for before its stores were open")
        assertionFailure("Await AppBootstrapping.sharedCoreDataStack() before the notebook is open")
        return notOpenYetStandIn
    }

    /// What `getSharedCoreDataStack` hands a caller that came too early.
    private static let notOpenYetStandIn = makeInMemoryStack()

    /// Opens the stack `sharedStackLoad` shares: in memory under XCTest
    /// (#15), else the launch's fallback chain, with each attempt's stores
    /// opened off the main thread. The stack's observers start as soon as
    /// it loads, for whoever asked first (#2).
    private static func openSharedStack() async -> CoreDataStack {
        // A hosted test may have asked synchronously first.
        if let existing = _sharedCoreDataStack { return existing }
        let interval = LaunchSignposts.begin("SharedStackLoad")
        defer { LaunchSignposts.end("SharedStackLoad", interval) }
        let stack = isRunningUnitTests
            ? makeInMemoryStack()
            : await loadSharedStack(create: createCoreDataStack, didLoad: startStoreObservers)
        _sharedCoreDataStack = stack
        #if DEBUG
        simulateDatabaseFailureIfRequested()
        #endif
        return stack
    }

    /// An empty stack in memory: hosted tests' notebook, and the stand-in.
    private static func makeInMemoryStack() -> CoreDataStack {
        do {
            return try CoreDataStack(enableCloudKit: false, inMemory: true)
        } catch {
            Logger.container.fault("No in-memory stack could be made: \(error.localizedDescription, privacy: .public)")
            return CoreDataStack.makeEmptyFallback()
        }
    }
}

/// Why an App Intent couldn't have the notebook, in plain words for Siri
/// and Shortcuts to say.
nonisolated enum NotebookUnavailableError: LocalizedError, Equatable {
    /// The stores were still opening when the intent stopped waiting.
    case stillOpening
    /// The stores couldn't be opened; the app's error screen says why.
    case couldNotOpen

    var errorDescription: String? {
        switch self {
        case .stillOpening:
            "Cosmic Daybook is still opening your notebook. Try again in a moment."
        case .couldNotOpen:
            "Cosmic Daybook couldn't open your notebook. Open the app to see why."
        }
    }
}

/// One piece of launch work that every caller shares: the first call starts
/// it, and every caller, then or later, gets its one result. The work runs
/// on the main actor, like its callers, and itself moves what is slow off
/// the main thread.
final class SharedLaunchLoad<Value: Sendable> {
    private let work: @MainActor () async -> Value
    private var task: Task<Value, Never>?
    /// The result, once the work has finished.
    private(set) var result: Value?

    init(_ work: @escaping @MainActor () async -> Value) {
        self.work = work
    }

    /// Starts the work, unless it has started.
    @discardableResult
    func start() -> Task<Value, Never> {
        if let task { return task }
        let task = Task {
            let value = await work()
            result = value
            return value
        }
        self.task = task
        return task
    }

    /// The result, waiting for the work if it hasn't finished.
    func value() async -> Value {
        if let result { return result }
        return await start().value
    }

    /// The result, or nil if the work is still running after `limit`. The
    /// work itself goes on, for the next caller.
    func value(waitingAtMost limit: Duration) async -> Value? {
        if let result { return result }
        let task = start()
        let race = FirstToFinish<Value>()
        return await withCheckedContinuation { continuation in
            race.continuation = continuation
            Task { race.finish(await task.value) }
            race.timer = Task {
                try? await Task.sleep(for: limit)
                race.finish(nil)
            }
        }
    }
}

/// Resumes a `value(waitingAtMost:)` caller once, with whichever finishes
/// first: the work, or the time limit.
private final class FirstToFinish<Value: Sendable> {
    var continuation: CheckedContinuation<Value?, Never>?
    var timer: Task<Void, Never>?

    func finish(_ value: Value?) {
        timer?.cancel()
        timer = nil
        continuation?.resume(returning: value)
        continuation = nil
    }
}
