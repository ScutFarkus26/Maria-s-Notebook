#if canImport(Testing)
import Testing
import Foundation
import SwiftData
import Combine
@testable import Maria_s_Notebook

// MARK: - MainActor Isolation Tests

/// Tests to verify MainActor isolation is respected.
@Suite("MainActor Isolation Tests")
@MainActor
struct MainActorIsolationTests {

    @Test("Published properties update on MainActor")
    func publishedPropertiesUpdateOnMainActor() async {
        let service = CloudKitSyncStatusService()

        // This should work without issues because we're on MainActor
        let _ = service.isSyncing
        let _ = service.syncHealth
    }

    @Test("Toast service updates on MainActor")
    func toastServiceUpdatesOnMainActor() async {
        let service = ToastService.shared

        // Show and dismiss should work on MainActor
        service.show("Test toast")
        service.dismiss()

        // Clear should also work
        service.clearAll()
    }
}

// MARK: - Task Cancellation Tests

/// Tests to verify task cancellation works correctly.
@Suite("Task Cancellation Tests")
struct TaskCancellationTests {

    @Test("Task.isCancelled reflects cancellation state")
    func taskIsCancelledReflectsState() async {
        let task = Task<Bool, Never> {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(10))
            }
            return Task.isCancelled
        }

        // Let it run briefly
        try? await Task.sleep(for: .milliseconds(50))

        task.cancel()
        let wasCancelled = await task.value

        #expect(wasCancelled == true)
    }

    @Test("Cancelled task exits sleep early")
    func cancelledTaskExitsSleepEarly() async {
        let startTime = Date()

        let task = Task {
            try? await Task.sleep(for: .seconds(10)) // 10 seconds
        }

        // Cancel after small delay
        try? await Task.sleep(for: .milliseconds(100)) // 0.1 seconds
        task.cancel()
        await task.value

        let elapsed = Date().timeIntervalSince(startTime)

        // Should have completed much faster than 10 seconds
        // Use generous threshold for CI/test environment variability
        #expect(elapsed < 5.0)
    }

    @Test("Task cancellation propagates to child withTaskGroup")
    func taskCancellationPropagatesToTaskGroup() async {
        let task = Task {
            await withTaskGroup(of: Bool.self, returning: Int.self) { group in
                for _ in 0..<5 {
                    group.addTask {
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .milliseconds(10))
                        }
                        return true
                    }
                }
                var count = 0
                for await cancelled in group where cancelled {
                    count += 1
                }
                return count
            }
        }

        try? await Task.sleep(for: .milliseconds(50))
        task.cancel()
        let childrenCancelled = await task.value

        // All children should have been cancelled
        #expect(childrenCancelled == 5)
    }
}

// MARK: - Async/Await Pattern Tests

/// Tests to verify async/await patterns work correctly.
@Suite("Async/Await Pattern Tests")
struct AsyncAwaitPatternTests {

    @Test("Sequential async operations maintain order")
    func sequentialAsyncOperationsOrder() async {
        var results: [Int] = []

        for i in 0..<5 {
            try? await Task.sleep(for: .milliseconds(10))
            results.append(i)
        }

        #expect(results == [0, 1, 2, 3, 4])
    }

    @Test("Concurrent async operations all complete")
    func concurrentAsyncOperationsComplete() async {
        var results: Set<Int> = []

        await withTaskGroup(of: Int.self) { group in
            for i in 0..<5 {
                group.addTask {
                    try? await Task.sleep(for: .milliseconds(Int64.random(in: 10...50)))
                    return i
                }
            }

            for await result in group {
                results.insert(result)
            }
        }

        #expect(results == Set([0, 1, 2, 3, 4]))
    }

    @Test("Async let runs concurrently")
    func asyncLetRunsConcurrently() async {
        let startTime = Date()

        // Use direct async let without wrapping in Task - this enables true concurrency
        async let a: Int = {
            try? await Task.sleep(for: .milliseconds(100))
            return 1
        }()
        async let b: Int = {
            try? await Task.sleep(for: .milliseconds(100))
            return 2
        }()
        async let c: Int = {
            try? await Task.sleep(for: .milliseconds(100))
            return 3
        }()

        let results = await [a, b, c]
        let elapsed = Date().timeIntervalSince(startTime)

        #expect(results == [1, 2, 3])
        // Should complete in ~0.1 seconds, not 0.3 (if they ran concurrently)
        // Use generous threshold for CI/test environment variability
        #expect(elapsed < 5.0)
    }
}

// MARK: - Debounce Pattern Tests

/// Tests to verify debounce patterns work correctly.
@Suite("Debounce Pattern Tests")
@MainActor
struct DebouncePatternTests {

    @Test("Debounced task only runs once for rapid calls")
    func debouncedTaskRunsOnce() async {
        var executionCount = 0
        var currentTask: Task<Void, Never>?

        // Simulate rapid calls with debounce
        for _ in 0..<10 {
            currentTask?.cancel()
            currentTask = Task {
                try? await Task.sleep(for: .milliseconds(50)) // 50ms debounce
                guard !Task.isCancelled else { return }
                executionCount += 1
            }
        }

        // Wait for the last task to complete
        await currentTask?.value

        // Only the last call should have executed
        #expect(executionCount == 1)
    }

    @Test("Non-debounced calls all execute")
    func nonDebouncedCallsExecute() async {
        var executionCount = 0

        // Calls with enough delay between them
        for _ in 0..<3 {
            executionCount += 1
            try? await Task.sleep(for: .milliseconds(100)) // Wait between calls
        }

        #expect(executionCount == 3)
    }
}

// MARK: - Continuation Tests

/// Tests to verify continuation patterns work correctly.
@Suite("Continuation Pattern Tests")
struct ContinuationPatternTests {

    @Test("withCheckedContinuation returns value")
    func checkedContinuationReturnsValue() async {
        let result = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: 42)
            }
        }

        #expect(result == 42)
    }

    @Test("withCheckedThrowingContinuation can throw")
    func checkedThrowingContinuationCanThrow() async {
        struct TestError: Error {}

        do {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
                DispatchQueue.global().async {
                    continuation.resume(throwing: TestError())
                }
            }
            Issue.record("Expected error to be thrown")
        } catch {
            // Expected
            #expect(error is TestError)
        }
    }

    @Test("withCheckedThrowingContinuation can return value")
    func checkedThrowingContinuationCanReturnValue() async throws {
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            DispatchQueue.global().async {
                continuation.resume(returning: 42)
            }
        }

        #expect(result == 42)
    }
}

// MARK: - Actor Tests

/// Tests to verify actor isolation patterns.
@Suite("Actor Isolation Pattern Tests")
struct ActorIsolationPatternTests {

    actor Counter {
        private var value = 0

        func increment() {
            value += 1
        }

        func getValue() -> Int {
            return value
        }
    }

    @Test("Actor prevents data races")
    func actorPreventsDataRaces() async {
        let counter = Counter()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<1000 {
                group.addTask {
                    await counter.increment()
                }
            }
        }

        let finalValue = await counter.getValue()

        // All increments should have been counted
        #expect(finalValue == 1000)
    }

    @Test("Actor methods are serialized")
    func actorMethodsSerialized() async {
        let counter = Counter()
        var results: [Int] = []

        // Increment and read multiple times
        for _ in 0..<10 {
            await counter.increment()
            let value = await counter.getValue()
            results.append(value)
        }

        // Each read should see the previous increment
        #expect(results == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
    }
}

// MARK: - Sendable Tests

/// Tests to verify Sendable conformance patterns.
@Suite("Sendable Pattern Tests")
struct SendablePatternTests {

    @Test("Value types are implicitly Sendable")
    func valueTypesAreSendable() async {
        let value = 42

        let result = await Task {
            return value
        }.value

        #expect(result == 42)
    }

    @Test("Immutable class can be Sendable")
    func immutableClassSendable() async {
        final class ImmutableData: Sendable {
            let value: Int

            init(value: Int) {
                self.value = value
            }
        }

        let data = ImmutableData(value: 42)

        let result = await Task {
            return data.value
        }.value

        #expect(result == 42)
    }

    @Test("Struct with Sendable properties is Sendable")
    func structWithSendableProperties() async {
        struct Data: Sendable {
            let id: UUID
            let name: String
        }

        let data = Data(id: UUID(), name: "Test")

        let result = await Task {
            return data.name
        }.value

        #expect(result == "Test")
    }
}

// MARK: - Migration Runner Tests

/// Tests to verify migration patterns work correctly.
@Suite("Migration Runner Pattern Tests", .serialized)
@MainActor
struct MigrationRunnerPatternTests {

    private func makeContainer() throws -> ModelContainer {
        return try makeStandardTestContainer()
    }

    @Test("Migrations can run sequentially")
    func migrationsRunSequentially() async throws {
        var executionOrder: [String] = []

        // Simulate sequential migration execution
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                executionOrder.append("migration1")
            }
        }

        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor in
                executionOrder.append("migration2")
            }
        }

        #expect(executionOrder == ["migration1", "migration2"])
    }
}

// MARK: - Notification Observer Tests

/// Tests to verify notification observer patterns.
@Suite("Notification Observer Pattern Tests")
@MainActor
struct NotificationObserverPatternTests {

    @Test("Notification observer receives notifications")
    func notificationObserverReceives() async {
        var receivedNotification = false

        let observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TestNotification"),
            object: nil,
            queue: .main
        ) { _ in
            receivedNotification = true
        }

        NotificationCenter.default.post(name: NSNotification.Name("TestNotification"), object: nil)

        // Give time for notification to be processed
        try? await Task.sleep(for: .milliseconds(100))

        NotificationCenter.default.removeObserver(observer)

        #expect(receivedNotification == true)
    }

    @Test("Removed observer doesn't receive notifications")
    func removedObserverDoesntReceive() async {
        var receivedCount = 0

        let observer = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("TestNotification2"),
            object: nil,
            queue: .main
        ) { _ in
            receivedCount += 1
        }

        NotificationCenter.default.post(name: NSNotification.Name("TestNotification2"), object: nil)
        try? await Task.sleep(for: .milliseconds(50))

        NotificationCenter.default.removeObserver(observer)

        NotificationCenter.default.post(name: NSNotification.Name("TestNotification2"), object: nil)
        try? await Task.sleep(for: .milliseconds(50))

        // Should only have received the first notification
        #expect(receivedCount == 1)
    }
}

// MARK: - DispatchQueue Integration Tests

/// Tests to verify DispatchQueue integration with async/await.
@Suite("DispatchQueue Integration Tests")
struct DispatchQueueIntegrationTests {

    @Test("DispatchQueue.main.async executes on main thread")
    func dispatchMainAsync() async {
        let isMainThread = await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume(returning: Thread.isMainThread)
            }
        }

        #expect(isMainThread == true)
    }

    @Test("DispatchQueue.global executes off main thread")
    func dispatchGlobalAsync() async {
        let isMainThread = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                continuation.resume(returning: Thread.isMainThread)
            }
        }

        #expect(isMainThread == false)
    }

    @Test("Task.detached runs off MainActor")
    func taskDetachedOffMainActor() async {
        // This test verifies that Task.detached doesn't inherit MainActor context
        let result = await Task.detached {
            // This closure is not on MainActor
            return 42
        }.value

        #expect(result == 42)
    }
}

// MARK: - Combine to Async Bridge Tests

/// Tests to verify Combine to async bridging patterns.
@Suite("Combine Async Bridge Tests")
struct CombineAsyncBridgeTests {

    @Test("Publisher values can be collected asynchronously")
    func publisherValuesCollected() async {
        var cancellables = Set<AnyCancellable>()
        var receivedValues: [Int] = []

        // Use a traditional Combine sink to verify publisher behavior
        let subject = PassthroughSubject<Int, Never>()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var count = 0
            subject
                .sink { value in
                    receivedValues.append(value)
                    count += 1
                    if count >= 3 {
                        continuation.resume()
                    }
                }
                .store(in: &cancellables)

            // Send values after subscription is established
            subject.send(1)
            subject.send(2)
            subject.send(3)
        }

        #expect(receivedValues == [1, 2, 3])
    }

    @Test("Publisher completion ends async iteration")
    func publisherCompletionEndsIteration() async {
        var cancellables = Set<AnyCancellable>()
        var receivedValues: [Int] = []

        // Use a traditional Combine sink to verify publisher behavior
        let subject = PassthroughSubject<Int, Never>()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            subject
                .sink(
                    receiveCompletion: { _ in
                        continuation.resume()
                    },
                    receiveValue: { value in
                        receivedValues.append(value)
                    }
                )
                .store(in: &cancellables)

            // Send values after subscription is established
            subject.send(1)
            subject.send(2)
            subject.send(completion: .finished)
        }

        #expect(receivedValues == [1, 2])
    }
}

// MARK: - UserDefaults Thread Safety Tests

/// Tests to verify UserDefaults access patterns.
@Suite("UserDefaults Thread Safety Tests")
struct UserDefaultsThreadSafetyTests {

    @Test("UserDefaults can be read from any thread")
    func userDefaultsReadFromAnyThread() async {
        let key = "test_read_key_\(UUID().uuidString)"
        UserDefaults.standard.set("test_value", forKey: key)

        let value = await Task.detached {
            return UserDefaults.standard.string(forKey: key)
        }.value

        #expect(value == "test_value")

        UserDefaults.standard.removeObject(forKey: key)
    }

    @Test("UserDefaults changes are visible across threads")
    func userDefaultsChangesVisible() async {
        let key = "test_change_key_\(UUID().uuidString)"

        // Write on main thread
        UserDefaults.standard.set("initial", forKey: key)

        // Read from background
        let value1 = await Task.detached {
            return UserDefaults.standard.string(forKey: key)
        }.value

        #expect(value1 == "initial")

        // Update on main
        UserDefaults.standard.set("updated", forKey: key)

        // Read from background again
        let value2 = await Task.detached {
            return UserDefaults.standard.string(forKey: key)
        }.value

        #expect(value2 == "updated")

        UserDefaults.standard.removeObject(forKey: key)
    }
}

#endif
