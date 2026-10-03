import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// MARK: - An original deleted by another device mid-batch

extension ClassroomShareReleaseTests {

    /// Deletes `id` here once the departed child's copies are confirmed, as another device's
    /// delete arriving from iCloud would.
    private func deleting(_ id: NSManagedObjectID, in fix: Fixture) -> ClassroomShareRelease.Environment {
        let container = fix.stack.container
        return fix.cloud.environment { step, batch in
            guard step == .copiesConfirmed, batch.studentKey != nil else { return }
            let context = container.newBackgroundContext()
            await context.perform {
                if let object = try? context.existingObject(with: id) { context.delete(object) }
                try? context.save()
            }
        }
    }

    private func marks(withID id: UUID, in fix: Fixture) -> Int {
        let request = CDFetchRequest(CDAttendanceRecord.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return fix.stack.viewContext.safeFetch(request).count
    }

    @Test("A mark another device deletes during the run, gone from iCloud too, doesn't come back as its copy")
    func originalDeletedElsewhere() async throws {
        let fix = try fixture()
        let mark = fix.departedMarks[1]
        let id = try #require(mark.id)
        let before = count("AttendanceRecord", in: fix)

        let report = try await release(fix, deleting(mark.objectID, in: fix))
        #expect(report.stoppedBecause == nil)
        #expect(marks(withID: id, in: fix) == 0)
        #expect(count("AttendanceRecord", in: fix) == before - 1)
    }

    @Test("A mark gone from this Mac while iCloud still has it stops the run, and its copy is kept")
    func originalVanishedButOnServer() async throws {
        let fix = try fixture()
        let mark = fix.departedMarks[1]
        let id = try #require(mark.id)
        fix.cloud.keepOnServer([mark.objectID])

        let report = try await release(fix, deleting(mark.objectID, in: fix))
        #expect(report.batchesDone == 0)
        #expect(report.stoppedBecause == ClassroomShareRelease.RunError.originalVanished.errorDescription)
        #expect(marks(withID: id, in: fix) == 1) // the private copy
        #expect(fix.cloud.exists(fix.departed.objectID)) // the batch's other originals stay
    }
}
