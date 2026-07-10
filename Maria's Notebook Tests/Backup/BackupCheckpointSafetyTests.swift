import CoreData
import Foundation
import Testing
@testable import Maria_s_Notebook

/// Guards the data-loss fix: a `.replace` restore must never delete existing
/// data when the pre-import safety checkpoint cannot be written. Without the
/// fix, a failed checkpoint was logged and the destructive import proceeded
/// anyway — wiping the user's data with no way back.
@MainActor
@Suite("Backup checkpoint safety")
struct BackupCheckpointSafetyTests {

    private struct CheckpointBoom: Error {}

    @Test("Checkpoint failure aborts before any destructive delete")
    func checkpointFailureAbortsBeforeDestructiveImport() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let context = stack.viewContext

        CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Lovelace")
        try context.save()

        let countRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Student")
        let before = try context.count(for: countRequest)
        #expect(before == 1)

        let manager = BackupTransactionManager()
        var importBodyRan = false

        await #expect(throws: CheckpointBoom.self) {
            _ = try await manager.executeWithRollback(
                viewContext: context,
                mode: .replace,
                shouldCreateCheckpoint: true,
                progress: { _, _ in },
                makeCheckpoint: { _, _ in throw CheckpointBoom() }
            ) { _ in
                // Must never run when the checkpoint fails. If it did, it would be
                // free to delete everything — which is exactly the bug under test.
                importBodyRan = true
                return BackupOperationSummary(
                    kind: .import,
                    fileName: "",
                    formatVersion: 17,
                    encryptUsed: false,
                    createdAt: Date(),
                    entityCounts: [:],
                    warnings: []
                )
            }
        }

        #expect(importBodyRan == false, "Import must not run when the checkpoint fails")
        let after = try context.count(for: countRequest)
        #expect(after == before, "Existing data must be untouched when the checkpoint fails")
    }
}
