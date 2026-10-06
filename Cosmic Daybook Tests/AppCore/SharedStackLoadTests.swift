import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Hunt of 2026-10-05, #2: a Siri intent run in the background launches the app
// with no scene (WWDC22 10032), so the window's bootstrap never runs, and the
// classroom-share guard it started never saw the attendance Siri marked: the
// mark stayed out of the share and never reached the assistants. The guard now
// starts when the shared stack loads, whoever asked for it first.

@Suite("Loading the shared stack")
@MainActor
struct SharedStackLoadTests {

    @Test("A stack that loads is handed to what must start with it, with no window involved")
    func loadedStackStartsItsObservers() async throws {
        var started: [CoreDataStack] = []
        let stack = await AppBootstrapping.loadSharedStack(
            create: { try CoreDataTestHelpers.makeInMemoryStack() },
            didLoad: { started.append($0) }
        )
        #expect(started.count == 1)
        #expect(started.first === stack)
    }

    // #15: the macOS test host is the real app in the real sandbox, and its
    // launch opened the guide's live notebook (and ran store surgery on it,
    // 2026-09-08). Under XCTest the shared stack is an empty one in memory.
    @Test("Hosted tests get the shared stack in memory, never the app's store files")
    func hostedTestsGetAnInMemoryStack() {
        let stores = AppBootstrapping.getSharedCoreDataStack().container.persistentStoreCoordinator.persistentStores
        #expect(!stores.isEmpty)
        #expect(stores.allSatisfy { $0.type == NSInMemoryStoreType })
        #expect(stores.allSatisfy { $0.url?.path.hasPrefix(CoreDataStack.storeDirectory().path) != true })
    }
}
