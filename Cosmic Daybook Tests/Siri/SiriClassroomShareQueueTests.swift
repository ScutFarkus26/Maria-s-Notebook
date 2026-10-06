import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// A Siri mark made with no window open still waits to go into the classroom
/// share. An intent run in the background brings up no scene, so the window
/// bootstrap that starts `SharedStoreOrphanGuard` never runs, and before
/// 2026-10-05 `SiriHost.didSave` did nothing: the mark stayed in the guide's
/// private store, where the assistants never saw it (hunt #2).
///
/// Unit tests never bootstrap the app, so the shared guard here is exactly the
/// one a background Siri launch has.
@Suite("Siri marks wait for the classroom share", .serialized)
@MainActor
struct SiriClassroomShareQueueTests {

    @Test("A Siri mark saved with no window bootstrap is queued for the classroom share")
    func siriMarkIsQueued() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        // The lead guide's private store beside the test's unified one: a mark
        // goes there on his devices (`CDAttendanceStore.destinationStore`).
        let privateStore = try stack.container.persistentStoreCoordinator.addPersistentStore(
            type: .inMemory,
            configuration: CoreDataStack.privateConfiguration,
            at: URL(fileURLWithPath: "/dev/null/private-\(UUID().uuidString)")
        )
        let context = stack.viewContext
        let student = CDStudent(context: context)
        student.id = UUID()
        student.firstName = "Maya"
        student.lastName = "Stone"
        student.enrollmentStatusRaw = CDStudent.EnrollmentStatus.enrolled.rawValue
        #expect(context.safeSave())
        SiriAttendanceChange.forget()
        defer { SiriAttendanceChange.forget() }

        let monday = try CoreDataTestHelpers.day("2026-10-12")
        let siri = SiriAttendance(stack: stack, role: .leadGuide, today: monday.addingTimeInterval(9 * 3_600))
        try await siri.mark(student, as: .present)

        let record = try #require(context.safeFetch(CDFetchRequest(CDAttendanceRecord.self)).first)
        #expect(record.objectID.persistentStore === privateStore)
        let uri = record.objectID.uriRepresentation().absoluteString
        defer { SharedStoreOrphanGuard.shared.removePending([uri]) }

        // Siri answers first; the mark is filed while Siri keeps the app awake.
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !SharedStoreOrphanGuard.shared.pendingURIs.contains(uri), ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(SharedStoreOrphanGuard.shared.pendingURIs.contains(uri))
    }
}
