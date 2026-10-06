import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// MARK: - A copy gone between its check and the originals' delete

extension ClassroomShareReleaseTests {

    @Test("A copy deleted after it was checked, just before the originals go, stops the run with every original kept")
    func copyGoneBeforeTheDeleteKeepsOriginals() async throws {
        let fix = try fixture()
        let container = fix.stack.container
        let env = fix.cloud.environment { step, batch in
            guard step == .copiesChecked, batch.studentKey != nil else { return }
            // Another device on an old build deletes the departed child's private copy.
            let move = batch.moves[0]
            let context = container.newBackgroundContext()
            await context.perform {
                let source = try? context.existingObject(with: move.source)
                let request = NSFetchRequest<NSManagedObject>(entityName: move.entity)
                for object in (try? context.fetch(request)) ?? [] where object.objectID != move.source {
                    if object.value(forKey: "id") as? UUID == source?.value(forKey: "id") as? UUID {
                        context.delete(object)
                    }
                }
                try? context.save()
            }
        }
        let report = try await release(fix, env)
        #expect(report.batchesDone == 0)
        #expect(report.stoppedBecause == ClassroomShareRelease.RunError.copyVanished.errorDescription)
        #expect(fix.cloud.exists(fix.departed.objectID)) // the shared original is still there
        #expect(fix.departedMarks.allSatisfy { fix.cloud.exists($0.objectID) })
        #expect(fix.cloud.awaiting.isEmpty) // nothing was deleted, so nothing waits on iCloud
    }
}
