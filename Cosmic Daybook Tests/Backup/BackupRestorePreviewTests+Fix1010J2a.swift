import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-10, P2 #90: the restore preview counted records in the
// shared store (a classroom someone else shared with this notebook) that a
// restore never touches, and a merge restore set every community attachment's
// file bytes to nothing, though backups don't carry them.
@Suite("Restore preview and merge (Fix1010 J2a)")
@MainActor
struct BackupRestorePreviewFix1010J2aTests {

    /// Two private children and three in a classroom shared with this
    /// notebook, saved in their stores.
    private static func splitNotebook() throws -> (NSManagedObjectContext, shared: [UUID]) {
        let context = try CoreDataTestHelpers.makeSplitStoreContext()
        let stores = try #require(context.persistentStoreCoordinator?.persistentStores)
        let privateStore = try #require(stores.first { $0.configurationName == CoreDataStack.privateConfiguration })
        let sharedStore = try #require(stores.first { $0.configurationName == CoreDataStack.sharedConfiguration })
        for name in ["Ada", "Grace"] {
            let student = CoreDataTestHelpers.seedStudent(in: context, firstName: name, lastName: "Mine")
            context.assign(student, to: privateStore)
        }
        var shared: [UUID] = []
        for name in ["Etty", "Sarah", "Maya"] {
            let student = CoreDataTestHelpers.seedStudent(in: context, firstName: name, lastName: "Shared")
            context.assign(student, to: sharedStore)
            shared.append(try #require(student.id))
        }
        #expect(CoreDataTestHelpers.save(context))
        return (context, shared)
    }

    @Test("Replace's preview counts only the records a replace removes: the notebook's own")
    func replacePreviewCountsThePrivateStoreOnly() throws {
        let (context, _) = try Self.splitNotebook()

        let analysis = BackupPreviewAnalyzer.analyze(
            digest: BackupPreviewDigest(), viewContext: context, mode: .replace, entityExists: { _, _ in false }
        )

        #expect(analysis.deletes["Student"] == 2, "the shared classroom's 3 children stay")
    }

    @Test("Merge's preview calls a record only in the shared store an add, as the restore makes it one")
    func mergePreviewLooksInThePrivateStoreOnly() throws {
        let (context, shared) = try Self.splitNotebook()
        let mine = try #require(context.safeFetch(CDFetchRequest(CDStudent.self)).first { $0.lastName == "Mine" }?.id)

        let index = EntityIDIndexCache(context: context)

        #expect(index.exists(CDStudent.self, id: mine))
        for id in shared {
            #expect(!index.exists(CDStudent.self, id: id))
        }
    }

    @Test("A merge restore keeps a community attachment's file; a new one arrives without")
    func mergeKeepsCommunityAttachmentData() async throws {
        let store = try BackupStreamingFixtures.makeStore()
        defer { store.remove() }
        let context = store.context
        let topic = CDCommunityTopicEntity(context: context)
        topic.title = "Lining up for recess"
        let attachment = CDCommunityAttachment(context: context)
        attachment.filename = "Plan.pdf"
        attachment.topic = topic
        let bytes = Data("the plan the children drew".utf8)
        attachment.data = bytes
        #expect(CoreDataTestHelpers.save(context))
        let url = store.archiveURL("Source")
        try await BackupRestoreFixtures.writeBackup(of: context, to: url)

        // Merged back over itself: the attachment is updated in place.
        _ = try await BackupRestoreFixtures.restore(url, into: context, mode: .merge)
        let kept = try #require(context.safeFetch(CDFetchRequest(CDCommunityAttachment.self)).first)
        context.refresh(kept, mergeChanges: false)
        #expect(kept.data == bytes)

        // Restored into an empty notebook: the record comes back, the bytes can't.
        let fresh = try CoreDataTestHelpers.makeContext()
        _ = try await BackupRestoreFixtures.restore(url, into: fresh, mode: .merge)
        let restored = try #require(fresh.safeFetch(CDFetchRequest(CDCommunityAttachment.self)).first)
        #expect(restored.filename == "Plan.pdf")
        #expect(restored.data == nil)
    }
}
