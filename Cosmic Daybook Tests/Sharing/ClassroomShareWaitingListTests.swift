import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// The classroom share's waiting list (`SharedStoreOrphanGuard`) keeps every
/// record that still has to go into the share (2026-10-05 hunt, #3, #21, #27):
/// a record made with sync off is queued, an edit to a shared student doesn't
/// fill the list with her marks, and the cap never pushes a waiting record out
/// behind ones that are gone or, once the classroom is shared, at all.
@Suite("Classroom share waiting list")
@MainActor
struct ClassroomShareWaitingListTests {

    /// A test stack with the lead guide's private store beside its unified one.
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
        try #require(UserDefaults(suiteName: "waiting-list-\(UUID().uuidString)"))
    }

    private func uri(_ object: NSManagedObject) -> String {
        object.objectID.uriRepresentation().absoluteString
    }

    /// Days off in the test's unified store: the save observer leaves them
    /// alone, so only `enqueue` lists them.
    private func daysOff(_ count: Int, in context: NSManagedObjectContext) -> [CDNonSchoolDay] {
        (0..<count).map { offset in
            let day = CDNonSchoolDay(context: context)
            day.date = Date(timeIntervalSinceReferenceDate: 800_000_000 + Double(offset) * 86_400)
            return day
        }
    }

    /// Waits up to `limit` for `condition`, for what the guard does after a save.
    private func eventually(_ limit: Duration = .seconds(3), _ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: limit)
        while !condition(), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test("With iCloud sync off, a new classroom record still waits for the share")
    func queuedWithSyncOff() async throws {
        let (stack, privateStore) = try makeStack()
        let guardian = SharedStoreOrphanGuard(defaults: try makeDefaults())
        guardian.start(coreDataStack: stack)
        #expect(!stack.isCloudKitActive)

        let context = stack.viewContext
        let day = CDNonSchoolDay(context: context)
        day.date = Date()
        context.assign(day, to: privateStore)
        #expect(context.safeSave())

        try await eventually { !guardian.pendingURIs.isEmpty }
        #expect(guardian.pendingURIs == [uri(day)])
    }

    @Test("An edit to a student queues her alone, not every mark of hers from this year")
    func editedStudentQueuesHerAlone() throws {
        let (stack, privateStore) = try makeStack()
        let context = stack.viewContext
        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = "Leah"
        context.assign(student, to: privateStore)
        for offset in 0..<3 {
            let mark = CDAttendanceRecord(context: context)
            mark.studentID = student.id?.uuidString ?? ""
            mark.date = Date().addingTimeInterval(Double(-offset) * 86_400)
            mark.status = .present
            context.assign(mark, to: privateStore)
        }
        #expect(context.safeSave())

        student.firstName = "Leah Rose"
        let queued = SharedStoreOrphanGuard.returningStudentRecords([student], in: stack)
        #expect(queued == [student.objectID])
    }

    @Test("Past the cap, with the classroom shared, nothing waiting is dropped")
    func noCapWhilePinned() async throws {
        let (stack, _) = try makeStack()
        let context = stack.viewContext
        let membership = CDClassroomMembership(context: context)
        membership.role = .leadGuide
        membership.classroomZoneID = "com.apple.coredata.cloudkit.share.TEST"
        let days = daysOff(SharedStoreOrphanGuard.maxPending + 1, in: context)
        #expect(context.safeSave())

        let guardian = SharedStoreOrphanGuard(defaults: try makeDefaults())
        guardian.start(coreDataStack: stack)
        guardian.enqueue(days.map(\.objectID))
        try await Task.sleep(for: .milliseconds(500)) // room for anything that would trim it
        #expect(guardian.pendingURIs.count == SharedStoreOrphanGuard.maxPending + 1)
        #expect(guardian.pendingURIs.first == uri(days[0]))
    }

    @Test("Past the cap, records deleted since leave first, and every one still waiting stays")
    func goneRecordsLeaveBeforeWaitingOnes() async throws {
        let (stack, _) = try makeStack()
        let context = stack.viewContext
        let waiting = daysOff(100, in: context)
        let doomed = daysOff(SharedStoreOrphanGuard.maxPending - 50, in: context)
        #expect(context.safeSave())

        let guardian = SharedStoreOrphanGuard(defaults: try makeDefaults())
        guardian.start(coreDataStack: stack)
        guardian.enqueue(waiting.map(\.objectID))
        guardian.enqueue(doomed.map(\.objectID))
        for day in doomed { context.delete(day) }
        #expect(context.safeSave())

        try await eventually { guardian.pendingURIs.count <= 100 }
        let pending = Set(guardian.pendingURIs)
        #expect(Set(waiting.map(uri)).isSubset(of: pending))
        #expect(pending.count == 100)
    }
}
