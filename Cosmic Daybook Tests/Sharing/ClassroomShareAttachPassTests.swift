import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// One attach pass at a time, never sharing a record twice, and a waiting list
/// that forgets only what a pass took as it found it (2026-10-05 hunt, #27,
/// #28, #31).
@Suite("Classroom share attach passes", .serialized)
@MainActor
struct ClassroomShareAttachPassTests {

    private func makeStack() throws -> (CoreDataStack, NSPersistentStore) {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let privateStore = try stack.container.persistentStoreCoordinator.addPersistentStore(
            type: .inMemory,
            configuration: CoreDataStack.privateConfiguration,
            at: URL(fileURLWithPath: "/dev/null/private-\(UUID().uuidString)")
        )
        return (stack, privateStore)
    }

    private func makeDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "attach-pass-\(UUID().uuidString)"))
    }

    private func uri(_ object: NSManagedObject) -> String {
        object.objectID.uriRepresentation().absoluteString
    }

    private func daysOff(_ count: Int, in context: NSManagedObjectContext) -> [CDNonSchoolDay] {
        (0..<count).map { _ in
            let day = CDNonSchoolDay(context: context)
            day.date = Date()
            return day
        }
    }

    // MARK: - The waiting list

    @Test("A record added again while a pass runs outlives that pass; one that failed stays too")
    func readdedDuringPassSurvives() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let days = daysOff(3, in: context)
        #expect(context.safeSave())
        let guardian = SharedStoreOrphanGuard(defaults: try makeDefaults())
        guardian.enqueue(days.map(\.objectID))

        let taken = guardian.pendingEntries
        guardian.enqueue([days[1].objectID]) // edited again mid-pass
        guardian.forget(taken, except: [uri(days[2])]) // the attach failed on the third
        #expect(guardian.pendingURIs == [uri(days[2]), uri(days[1])])
    }

    @Test("Set Up Classroom Sharing forgets what it found waiting, except what its attach failed on")
    func setupKeepsItsFailures() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let days = daysOff(3, in: context)
        #expect(context.safeSave())
        let current = days.enumerated().map { SharedStoreOrphanGuard.Entry(uri: uri($1), stamp: Double($0 + 1)) }
        let failed: Set<String> = [uri(days[0])]
        let remaining = SharedStoreOrphanGuard.remaining(current, after: current, keeping: failed)
        #expect(remaining.map(\.uri) == [uri(days[0])])
    }

    @Test("Past the cap with the classroom not shared, the oldest still waiting go after the deleted")
    func capStillAppliesUnshared() async throws {
        let (stack, _) = try makeStack()
        let context = stack.viewContext
        let days = daysOff(SharedStoreOrphanGuard.maxPending + 5, in: context)
        #expect(context.safeSave())
        let guardian = SharedStoreOrphanGuard(defaults: try makeDefaults())
        guardian.start(coreDataStack: stack)
        guardian.enqueue(days.map(\.objectID))
        await guardian.prune()
        #expect(guardian.pendingURIs.count == SharedStoreOrphanGuard.maxPending)
        #expect(guardian.pendingURIs.first == uri(days[5]))
    }

    @Test("Until the school-year start reaches this device, a record that looks like last year's keeps waiting")
    func provisionalStartKeepsLastYear() async throws {
        let (stack, privateStore) = try makeStack()
        let context = stack.viewContext
        let cutoff = AppCalendar.startOfDay(Date(timeIntervalSinceReferenceDate: 810_000_000))
        let student = CDStudent(context: context)
        student.id = UUID()
        context.assign(student, to: privateStore)
        // The class met on the 25th; the fallback start is a week later.
        let early = CDAttendanceRecord(context: context)
        early.studentID = student.id?.uuidString ?? ""
        early.date = cutoff.addingTimeInterval(-7 * 86_400)
        context.assign(early, to: privateStore)
        #expect(context.safeSave())

        let guardian = SharedStoreOrphanGuard(defaults: try makeDefaults())
        guardian.start(coreDataStack: stack)
        guardian.enqueue([early.objectID])

        guardian.scope = { ClassroomShareScope(cutoff: cutoff, isProvisional: true) }
        await guardian.prune()
        #expect(guardian.pendingURIs == [uri(early)])

        guardian.scope = { ClassroomShareScope(cutoff: cutoff) }
        await guardian.prune()
        #expect(guardian.pendingURIs.isEmpty)
    }

    @Test("A returning student found unshared brings this year's marks, and only hers")
    func returningStudentBringsHerMarks() async throws {
        let (stack, privateStore) = try makeStack()
        let context = stack.viewContext
        let cutoff = AppCalendar.startOfDay(Date(timeIntervalSinceReferenceDate: 810_000_000))
        func student() -> CDStudent {
            let student = CDStudent(context: context)
            student.id = UUID()
            context.assign(student, to: privateStore)
            return student
        }
        func mark(_ student: CDStudent, _ days: Double) -> CDAttendanceRecord {
            let record = CDAttendanceRecord(context: context)
            record.studentID = (student.id?.uuidString ?? "").lowercased()
            record.date = cutoff.addingTimeInterval(days * 86_400)
            context.assign(record, to: privateStore)
            return record
        }
        let leah = student()
        let other = student()
        let thisYear = mark(leah, 3)
        _ = mark(leah, -40)
        _ = mark(other, 3)
        #expect(context.safeSave())

        let found = await SharedStoreOrphanGuard.thisYearsAttendance(
            ofStudents: [leah.objectID], storeID: privateStore.identifier,
            container: stack.container, scope: ClassroomShareScope(cutoff: cutoff)
        )
        #expect(found == [thisYear.objectID])
    }

    // MARK: - Never sharing a record twice

    @Test("Every chunk is checked again just before it's shared, the first one too")
    func firstChunkRechecked() async throws {
        let context = try CoreDataTestHelpers.makeContext()
        let days = daysOff(3, in: context)
        #expect(context.safeSave())
        let ids = days.map(\.objectID)
        // The first went into the share with a related record after the caller looked.
        let alreadyShared = ids[0]
        let calls = SharedCalls()
        let steps = ClassroomShareAttach.Steps(
            unshared: { candidates in candidates.filter { $0 != alreadyShared } },
            share: { chunk in await calls.record(chunk) }
        )
        let outcome = await ClassroomShareAttach.attach(ids, using: steps)
        #expect(await calls.all == [Array(ids[1...])])
        #expect(outcome.attached == 3)
        #expect(outcome.failed.isEmpty)
    }

    @Test("While one attach holds the lock, the next waits its turn")
    func lockMakesTheNextWait() async throws {
        let lock = ClassroomShareAttachLock()
        let order = EventLog()
        await lock.acquire()
        let second = Task { @MainActor in
            await lock.run { order.items.append("second") }
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(order.items.isEmpty)
        order.items.append("first")
        lock.release()
        await second.value
        #expect(order.items == ["first", "second"])
        #expect(!lock.isHeld)
    }
}

/// The order things happened in.
@MainActor
private final class EventLog {
    var items: [String] = []
}

/// What a test's stand-in for `container.share(_:to:)` was asked to share.
private actor SharedCalls {
    private(set) var all: [[NSManagedObjectID]] = []
    func record(_ chunk: [NSManagedObjectID]) { all.append(chunk) }
}
