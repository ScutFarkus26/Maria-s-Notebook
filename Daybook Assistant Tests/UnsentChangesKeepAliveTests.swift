import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// What leaving the foreground waits for, on an in-memory stack. CloudKit's
// export events can't be made in a test, so they're reported through
// `exported(startedAt:)`, which is all the event observer does.
@Suite("Unsent changes keep-alive")
@MainActor
struct UnsentChangesKeepAliveTests {

    private let stack: CoreDataStack

    init() throws {
        stack = try AssistantTestSupport.makeStack()
    }

    private var context: NSManagedObjectContext { stack.viewContext }

    private func saveAMark() {
        let record = CDAttendanceRecord(context: context)
        record.id = UUID()
        #expect(context.safeSave())
    }

    @Test("A save is unsent until an export that started after it finishes")
    func exportAfterTheSave() throws {
        let keepAlive = UnsentChangesKeepAlive(viewContext: context)
        #expect(!keepAlive.hasUnsentWork)

        saveAMark()
        let since = try #require(keepAlive.unsentSince)
        #expect(keepAlive.hasUnsentWork)

        // An export already running when she tapped doesn't hold the mark.
        keepAlive.exported(startedAt: since.addingTimeInterval(-1))
        #expect(keepAlive.hasUnsentWork)

        keepAlive.exported(startedAt: Date())
        #expect(!keepAlive.hasUnsentWork)
    }

    @Test("A save with nothing in it leaves nothing unsent")
    func emptySave() {
        let keepAlive = UnsentChangesKeepAlive(viewContext: context)
        #expect(context.safeSave())
        #expect(!keepAlive.hasUnsentWork)
    }

    @Test("A second save waits for the export after the first, not a later one")
    func firstSaveCounts() throws {
        let keepAlive = UnsentChangesKeepAlive(viewContext: context)
        saveAMark()
        let first = try #require(keepAlive.unsentSince)
        saveAMark()
        #expect(keepAlive.unsentSince == first)
    }

    @Test("The app's own sending counts as unsent work")
    func appWork() {
        let busy = Flag(true)
        let keepAlive = UnsentChangesKeepAlive(viewContext: context, isBusy: { busy.value })
        #expect(keepAlive.hasUnsentWork)
        busy.value = false
        #expect(!keepAlive.hasUnsentWork)
    }

    @Test("Waiting returns when the export arrives, at once with nothing unsent, and at the limit otherwise")
    func waiting() async {
        let keepAlive = UnsentChangesKeepAlive(viewContext: context)
        await keepAlive.waitUntilSent(upTo: .seconds(60))

        saveAMark()
        Task { keepAlive.exported(startedAt: Date()) }
        await keepAlive.waitUntilSent(upTo: .seconds(60))
        #expect(!keepAlive.hasUnsentWork)

        saveAMark()
        let clock = ContinuousClock()
        let waited = await clock.measure { await keepAlive.waitUntilSent(upTo: .milliseconds(50)) }
        #expect(waited < .seconds(5))
        #expect(keepAlive.hasUnsentWork)
    }
}

@MainActor
private final class Flag {
    var value: Bool
    init(_ value: Bool) { self.value = value }
}
