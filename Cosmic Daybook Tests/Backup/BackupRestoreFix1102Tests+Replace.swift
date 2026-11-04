import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-11-02, the Replace findings: a Replace on the sharing Mac
// deleted the classroom share's records and inserted copies outside the
// share (#2); it cleared types the backup had no rows for, from an entry
// that didn't decode or a format older than the type (#10); and restored
// project sessions weren't linked to their project (#7).

@Suite("Restore fixes (2026-11-02): Replace keeps the classroom share's records in place", .serialized)
@MainActor
struct BackupReplaceInPlaceTests {

    /// A notebook on two in-memory stores carrying the real Private and
    /// Shared configurations: the lead guide's Mac, where the share's zone
    /// lives in the private store, with a classroom someone else shared in
    /// the shared store.
    private static func twoStoreNotebook() throws -> (NSManagedObjectContext, [String: NSPersistentStore]) {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: try CoreDataStack.sharedModel())
        var stores: [String: NSPersistentStore] = [:]
        for configuration in [CoreDataStack.privateConfiguration, CoreDataStack.sharedConfiguration] {
            stores[configuration] = try coordinator.addPersistentStore(
                type: .inMemory, configuration: configuration,
                at: URL(fileURLWithPath: "/dev/null").appendingPathComponent(configuration)
            )
        }
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return (context, stores)
    }

    @Test("A Replace updates the share's records where they are and deletes only those the backup lacks")
    func replaceUpdatesSharedRecordsInPlace() async throws {
        let (context, stores) = try Self.twoStoreNotebook()
        let privateStore = try #require(stores[CoreDataStack.privateConfiguration])
        let sharedStore = try #require(stores[CoreDataStack.sharedConfiguration])
        var students: [String: CDStudent] = [:]
        for (name, store) in [("Ada", privateStore), ("Gone", privateStore), ("Etty", sharedStore)] {
            let student = CoreDataTestHelpers.seedStudent(in: context, firstName: name, lastName: "Here")
            context.assign(student, to: store)
            students[name] = student
        }
        try context.save()
        let ada = try #require(students["Ada"])
        let (adaID, adaObjectID) = (try #require(ada.id), ada.objectID)
        let goneID = try #require(students["Gone"]?.id)
        let ettyID = try #require(students["Etty"]?.id)

        var backup = Fix1102.payload(of: context)
        backup.students = backup.students.filter { $0.id == adaID }
        backup.students[0].values["firstName"] = .string("Ada (backup)")

        let preview = Fix1102.analyze(BackupPreviewDigest(payload: backup), against: context, mode: .replace)
        #expect(preview.inserts["Student"] == 0)
        #expect(preview.skips["Student"] == 1, "Ada, updated where she is")
        #expect(preview.deletes["Student"] == 1, "Gone; the shared classroom's child isn't counted")

        try await Fix1102.restore(backup, into: context, mode: .replace)
        let after = context.safeFetch(CDFetchRequest(CDStudent.self))
        let restored = try #require(after.first { $0.id == adaID })
        #expect(restored.objectID == adaObjectID, "the same record, so its CloudKit identity and zone stay")
        #expect(restored.objectID.persistentStore === privateStore)
        #expect(restored.firstName == "Ada (backup)", "with the backup's values")
        #expect(!after.contains { $0.id == goneID }, "a child the backup lacks is deleted")
        let etty = try #require(after.first { $0.id == ettyID }, "another guide's classroom is left alone")
        #expect(etty.objectID.persistentStore === sharedStore)
        #expect(after.count == 2)
    }

    @Test("A Merge on two stores updates a saved record where it is")
    func mergeUpdatesASavedRecordOnTwoStores() async throws {
        let (context, stores) = try Self.twoStoreNotebook()
        let privateStore = try #require(stores[CoreDataStack.privateConfiguration])
        let ada = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada", lastName: "Here")
        context.assign(ada, to: privateStore)
        try context.save()
        let objectID = ada.objectID

        var backup = Fix1102.payload(of: context)
        backup.students[0].values["firstName"] = .string("Ada (backup)")
        backup.students[0].values["modifiedAt"] = .date(Date().addingTimeInterval(60))

        // The importers `insert` the saved record they update; giving it a
        // store again used to throw at the save.
        try await Fix1102.restore(backup, into: context, mode: .merge)
        let restored = try #require(context.safeFetch(CDFetchRequest(CDStudent.self)).first)
        #expect(restored.objectID == objectID)
        #expect(restored.firstName == "Ada (backup)")
        #expect(!context.hasChanges)
    }

    @Test("Deleting a staple the backup lacks keeps the history rows the backup holds")
    func replaceKeepsABackedUpChildOfARecordItLacks() async throws {
        let (context, _) = try Self.twoStoreNotebook()
        let staple = NSEntityDescription.insertNewObject(forEntityName: "Supply", into: context)
        let stapleID = UUID()
        staple.setValue(stapleID, forKey: "id")
        staple.setValue("Paper", forKey: "name")
        let history = NSEntityDescription.insertNewObject(forEntityName: "SupplyTransaction", into: context)
        let historyID = UUID()
        history.setValue(historyID, forKey: "id")
        history.setValue(stapleID.uuidString, forKey: "supplyID")
        history.setValue(staple, forKey: "supply")
        try context.save()

        var backup = Fix1102.payload(of: context)
        backup.supplies = []
        #expect(backup.supplyTransactions?.map(\.id) == [historyID])

        try await Fix1102.restore(backup, into: context, mode: .replace)
        let ids = { (entity: String) in
            context.safeFetch(NSFetchRequest<NSManagedObject>(entityName: entity))
                .compactMap { $0.value(forKey: "id") as? UUID }
        }
        #expect(ids("Supply").isEmpty, "the staple the backup lacks is deleted")
        #expect(ids("SupplyTransaction") == [historyID], "its history row, which the backup holds, stays")
    }
}

@Suite("Restore fixes (2026-11-02): Replace and entries it can't read", .serialized)
@MainActor
struct BackupReplaceUnreadableTests {
    private typealias Restore = BackupRestoreFixtures

    /// A backup of Ada and a fire-drill procedure, with `broken`'s entry
    /// given a row that doesn't decode; and a notebook holding Grace and a
    /// lockdown procedure to restore it into.
    private static func brokenBackup(
        _ broken: String, in store: BackupStreamingFixtures.Store
    ) async throws -> (url: URL, notebook: NSManagedObjectContext) {
        let source = store.context
        CoreDataTestHelpers.seedStudent(in: source, firstName: "Ada", lastName: "Backed")
        let drill = CDProcedure(context: source)
        drill.title = "Fire drill"
        try source.save()
        let url = store.archiveURL("Source")
        _ = try await BackupWriter.write(viewContext: source, to: url)
        let contents = try BackupStreamingFixtures.contents(of: url)
        let entries = try contents.paths.map { path in
            let body = try #require(contents.bodies[path])
            return (path: path, data: path == Restore.path(broken) ? body + Data("{\"id\":5}\n".utf8) : body)
        }
        #expect(entries.contains { $0.path == Restore.path(broken) }, "the backup has a \(broken) entry")
        let brokenURL = store.archiveURL("Broken \(broken)")
        try Restore.writeArchive(entries, to: brokenURL)

        let notebook = try CoreDataTestHelpers.makeContext()
        CoreDataTestHelpers.seedStudent(in: notebook, firstName: "Grace", lastName: "Here")
        let lockdown = CDProcedure(context: notebook)
        lockdown.title = "Lockdown"
        try notebook.save()
        return (brokenURL, notebook)
    }

    private static func procedures(in context: NSManagedObjectContext) -> [String] {
        context.safeFetch(CDFetchRequest(CDProcedure.self)).map(\.title).sorted()
    }

    @Test("A Replace won't run when the backup's children can't be read, and its preview says so")
    func replaceRefusesWhenARequiredTypeIsUnreadable() async throws {
        let store = try BackupStreamingFixtures.makeStore()
        defer { store.remove() }
        let (url, notebook) = try await Self.brokenBackup("Student", in: store)

        let preview = try await BackupImporter.decodePreview(at: url)
        #expect(preview.digest.skippedEntityNames == ["Student"])
        #expect(BackupImporter.requiredTypesUnreadable(in: preview.warnings) == ["Student"])
        let analysis = Fix1102.analyze(preview.digest, against: notebook, mode: .replace)
        #expect(analysis.deletes["Student"] == nil, "nothing of it removed")

        let error = await #expect(throws: (any Error).self) {
            _ = try await Restore.restore(url, into: notebook, mode: .replace)
        }
        #expect(error?.localizedDescription.hasPrefix("Part of this backup couldn't be read (students)") == true)
        #expect(Fix1102.students(in: notebook).values.sorted() == ["Grace"], "the notebook as it was")
        #expect(Self.procedures(in: notebook) == ["Lockdown"])
        #expect(!notebook.hasChanges)
    }

    @Test("A Replace leaves a type whose entry couldn't be read, and replaces the rest")
    func replaceLeavesAnUnreadableOptionalType() async throws {
        let store = try BackupStreamingFixtures.makeStore()
        defer { store.remove() }
        let (url, notebook) = try await Self.brokenBackup("Procedure", in: store)

        let preview = try await BackupImporter.decodePreview(at: url)
        #expect(preview.digest.skippedEntityNames == ["Procedure"])
        #expect(BackupImporter.requiredTypesUnreadable(in: preview.warnings).isEmpty, "Replace is offered")
        #expect(Fix1102.analyze(preview.digest, against: notebook, mode: .replace).deletes["Procedure"] == nil)

        _ = try await Restore.restore(url, into: notebook, mode: .replace)
        #expect(Fix1102.students(in: notebook).values.sorted() == ["Ada"], "the children are the backup's")
        #expect(Self.procedures(in: notebook) == ["Lockdown"], "the procedures stay: the backup's couldn't be read")
    }

    @Test("Recall checks joined at v20: a Replace from an older backup keeps them")
    func recallChecksJoinedAtV20() async throws {
        let since = Dictionary(uniqueKeysWithValues: BackupEntityTable.entities.map { ($0.name, $0.firstFormat) })
        #expect(since["LessonRecallCheck"] == 20)

        let context = try CoreDataTestHelpers.makeContext()
        let check = NSEntityDescription.insertNewObject(forEntityName: "LessonRecallCheck", into: context)
        check.setValue(UUID(), forKey: "id")
        try context.save()
        var backup = Fix1102.payload(of: context)
        backup.recallChecks = nil
        let count = { try context.count(for: NSFetchRequest<NSManagedObject>(entityName: "LessonRecallCheck")) }

        try await Fix1102.restore(backup, format: 19, into: context, mode: .replace)
        #expect(try count() == 1, "a v19 backup may predate recall checks")
        try await Fix1102.restore(backup, format: 20, into: context, mode: .replace)
        #expect(try count() == 0, "a v20 backup holds them, and has none")
    }
}

@Suite("Restore fixes (2026-11-02): restored project sessions", .serialized)
@MainActor
struct BackupRestoreProjectSessionTests {

    @Test("A restored session is linked to its project, by Merge and by Replace", arguments: [
        BackupService.RestoreMode.merge, .replace
    ])
    func restoredSessionIsLinked(mode: BackupService.RestoreMode) async throws {
        let source = try CoreDataTestHelpers.makeContext()
        let project = CDProject(context: source)
        project.title = "Charlotte's Web"
        let session = CDProjectSession(context: source)
        session.projectID = try #require(project.id).uuidString
        session.project = project
        try source.save()
        let backup = Fix1102.payload(of: source)

        let target = try CoreDataTestHelpers.makeContext()
        try await Fix1102.restore(backup, into: target, mode: mode)
        let restored = try #require(target.safeFetch(CDFetchRequest(CDProjectSession.self)).first)
        #expect(restored.project?.id == project.id, "reached through the relationship, as the app reads it")
    }
}
