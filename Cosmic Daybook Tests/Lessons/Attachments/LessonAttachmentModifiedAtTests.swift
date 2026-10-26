import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Lesson file attachments, Phase 1: `LessonAttachment.modifiedAt` (schema 22,
/// backup v44). A store from schema 21 opens with it, a backup carries it, and
/// a row from an older backup reads it as its `attachedAt`.
@Suite("Lesson files: modifiedAt (schema 22, backup v44)", .serialized)
@MainActor
struct LessonAttachmentModifiedAtTests {

    static let attached = Date(timeIntervalSince1970: 1_790_000_000)
    static let changed = Date(timeIntervalSince1970: 1_790_086_400)

    // MARK: - Backup

    /// A lesson with one file, attached at `attached` and changed at `changed`.
    private func seed(in context: NSManagedObjectContext) throws -> CDLessonAttachment {
        let lesson = CoreDataTestHelpers.seedLesson(
            in: context, name: "Area of a Circle", area: "Geometry", sequence: "Circle"
        )
        lesson.id = UUID()
        let attachment = CDLessonAttachment(context: context)
        attachment.fileName = "Area of a Circle — remade album pages.pdf"
        attachment.fileRelativePath = "Geometry/Circle/Area of a Circle - remade album pages.pdf"
        attachment.fileType = "pdf"
        attachment.fileSizeBytes = 605_635
        attachment.notes = "From the remade Geometry album"
        attachment.attachedAt = Self.attached
        attachment.modifiedAt = Self.changed
        attachment.lesson = lesson
        try context.save()
        return attachment
    }

    /// The context's records as a backup file carries them: written to NDJSON
    /// by the live writer and read back by the live reader.
    private func backup(of context: NSManagedObjectContext) throws -> (BackupPayload, [BackupEntityEntry]) {
        var payload = BackupService().collectPayload(viewContext: context)
        payload.preferences = PreferencesDTO(values: [:])
        let entries = try BackupWriter.serializeEntries(from: payload)
        let manifest = BackupArchiveManifest(
            formatVersion: BackupWriter.formatVersion, createdAt: Date(),
            appVersion: "", appBuild: "", device: "", entityCounts: [:], originStores: [:]
        )
        let decoded = BackupReader.DecodedBackup(manifest: manifest, entries: entries, preferences: nil)
        let (read, warnings) = BackupImporter.reconstructPayload(from: decoded)
        #expect(warnings.isEmpty, "\(warnings)")
        return (read, entries)
    }

    private func restore(
        _ payload: BackupPayload, format: Int, into context: NSManagedObjectContext, mode: BackupService.RestoreMode
    ) async throws {
        let envelope = BackupEnvelope(
            formatVersion: format, encrypted: false, createdAt: Self.changed, fileName: "modifiedAt", entityCounts: [:]
        )
        _ = try await BackupService().importPayload(
            payload: payload, envelope: envelope, viewContext: context, mode: mode,
            appRouter: AppRouter(), progress: { _, _ in }
        )
    }

    private func restored(_ id: UUID?, in context: NSManagedObjectContext) throws -> CDLessonAttachment? {
        let id = try #require(id)
        let request = CDFetchRequest(CDLessonAttachment.self)
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }

    @Test("A backup carries modifiedAt, and a restore brings it back")
    func backupRoundTrip() async throws {
        let source = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let attachment = try seed(in: source)
        let (payload, entries) = try backup(of: source)

        let entry = try #require(entries.first { $0.entityName == "LessonAttachment" })
        #expect(String(bytes: entry.ndjson, encoding: .utf8)?.contains(#""modifiedAt""#) == true)
        #expect(BackupWriter.formatVersion == 44)
        #expect(BackupReader.supportedFormatVersions.contains(43))
        #expect(BackupReader.supportedFormatVersions.contains(42))

        let target = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        try await restore(payload, format: BackupWriter.formatVersion, into: target, mode: .replace)

        let back = try #require(try restored(attachment.id, in: target))
        #expect(back.modifiedAt == Self.changed)
        #expect(back.attachedAt == Self.attached)
        #expect(back.fileName == "Area of a Circle — remade album pages.pdf")
        #expect(back.lastChanged == Self.changed)
    }

    @Test("A row from a v42 backup reads modifiedAt as its attachedAt, in a Replace and in a merge")
    func predatedRowsReadAttachedAt() async throws {
        let source = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let attachment = try seed(in: source)
        var old = try backup(of: source).0
        // The same record as a v42 backup has it: no modifiedAt.
        var row = try #require(old.lessonAttachments?.first)
        row.values["modifiedAt"] = nil
        old.lessonAttachments = [row]

        let fresh = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        try await restore(old, format: 42, into: fresh, mode: .replace)
        let replaced = try #require(try restored(attachment.id, in: fresh))
        #expect(replaced.modifiedAt == Self.attached)

        // Merged onto the record, which has changed since: the backup's row
        // (its name, file and size as of then) was last changed when attached.
        try await restore(old, format: 42, into: source, mode: .merge)
        #expect(attachment.modifiedAt == Self.attached)
        #expect(attachment.notes == "From the remade Geometry album", "the row was restored")

        // A current backup's row without one means the record never had one.
        let current = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        try await restore(old, format: BackupWriter.formatVersion, into: current, mode: .replace)
        let plain = try #require(try restored(attachment.id, in: current))
        #expect(plain.modifiedAt == nil)
        #expect(plain.lastChanged == Self.attached)
    }

    @Test("The Sample Class's copy of a lesson file keeps when it last changed")
    func sampleClassMirrorsModifiedAt() throws {
        let real = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let sample = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        let attachment = try seed(in: real)

        try SampleClassroomSeeder.mirror(lessons: SampleClassroomSeeder.lessonSnapshots(from: real), into: sample)

        let copy = try #require(try restored(attachment.id, in: sample))
        #expect(copy.modifiedAt == Self.changed)
        #expect(copy.attachedAt == Self.attached)
    }

    @Test("Every stand-in names two attributes of the same kind on a backed-up entity")
    func standInsAreReal() throws {
        let model = try CoreDataStack.sharedModel()
        for (entityName, standIns) in BackupFieldsAddedLater.standIns {
            let entity = try #require(model.entitiesByName[entityName], "\(entityName) is in the model")
            #expect(BackupEntityTable.names.contains(entityName), "\(entityName) is backed up")
            for standIn in standIns {
                let attribute = try #require(entity.attributesByName[standIn.attribute])
                let from = try #require(entity.attributesByName[standIn.from])
                #expect(attribute.isOptional, "\(entityName).\(standIn.attribute) can be missing")
                #expect(attribute.attributeType == from.attributeType)
                #expect((18...BackupWriter.formatVersion).contains(standIn.version))
            }
        }
        #expect(BackupFieldsAddedLater.standIns(from: 42, in: "LessonAttachment").map(\.attribute) == ["modifiedAt"])
        #expect(BackupFieldsAddedLater.standIns(from: 43, in: "LessonAttachment").isEmpty)
    }

    // MARK: - Schema 21

    /// The model as schema 21 had it: no `LessonAttachment.modifiedAt`.
    private func schema21Model() throws -> NSManagedObjectModel {
        let url = try #require(Bundle.main.url(forResource: CoreDataStack.modelName, withExtension: "momd"))
        let loaded = try #require(NSManagedObjectModel(contentsOf: url))
        let model = try #require(loaded.copy() as? NSManagedObjectModel)
        let attachment = try #require(model.entitiesByName["LessonAttachment"])
        attachment.properties = attachment.properties.filter { $0.name != "modifiedAt" }
        for entity in model.entities {
            // Plain objects: the bundle's model keeps the CD… classes to itself.
            entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        }
        // The copy's configurations, routed as the app routes them.
        let shared = CoreDataStack.sharedEntityNames
        let routed = CoreDataStack.privateEntityNames.union(shared)
        model.setEntities(
            model.entities.filter { shared.contains($0.name ?? "") },
            forConfigurationName: CoreDataStack.sharedConfiguration
        )
        model.setEntities(
            model.entities.filter { routed.contains($0.name ?? "") },
            forConfigurationName: CoreDataStack.privateConfiguration
        )
        return model
    }

    private func container(_ model: NSManagedObjectModel, in directory: URL) -> NSPersistentContainer {
        let container = NSPersistentContainer(name: CoreDataStack.modelName, managedObjectModel: model)
        container.persistentStoreDescriptions = [CoreDataStack.privateConfiguration, CoreDataStack.sharedConfiguration]
            .map { configuration in
                let description = CoreDataStack.makeStoreDescription(
                    url: directory.appendingPathComponent("\(configuration).sqlite"), configuration: configuration
                )
                CoreDataStack.enableHistoryTracking(description)
                return description
            }
        return container
    }

    private func load(_ container: NSPersistentContainer) throws {
        var loadError: Error?
        container.loadPersistentStores { _, error in
            if let error { loadError = error }
        }
        if let loadError { throw loadError }
    }

    private func privateStore(of container: NSPersistentContainer) throws -> NSPersistentStore {
        try #require(container.persistentStoreCoordinator.persistentStores.first {
            $0.configurationName == CoreDataStack.privateConfiguration
        })
    }

    @Test("A schema-21 store opens with schema 22: its lesson files stay, with no modifiedAt until one is set")
    func schema21StoreMigrates() throws {
        #expect(CoreDataStack.currentSchemaVersion == 22)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("lesson-files-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let id = UUID()

        // 1. Schema 21: a lesson with a file, in the guide's private store.
        try autoreleasepool {
            let old = container(try schema21Model(), in: directory)
            try load(old)
            let context = old.viewContext
            let store = try privateStore(of: old)
            let lesson = NSEntityDescription.insertNewObject(forEntityName: "Lesson", into: context)
            lesson.setValue(UUID(), forKey: "id")
            lesson.setValue("Area of a Circle", forKey: "name")
            context.assign(lesson, to: store)
            let file = NSEntityDescription.insertNewObject(forEntityName: "LessonAttachment", into: context)
            file.setValue(id, forKey: "id")
            file.setValue("Area of a Circle.pdf", forKey: "fileName")
            file.setValue(Self.attached, forKey: "attachedAt")
            file.setValue(lesson, forKey: "lesson")
            context.assign(file, to: store)
            try context.save()
            for store in old.persistentStoreCoordinator.persistentStores {
                try old.persistentStoreCoordinator.remove(store)
            }
        }

        // 2. Schema 22, prepared exactly as `CoreDataStack.init` prepares it.
        let model = try CoreDataStack.sharedModel()
        let new = container(model, in: directory)
        try CoreDataStack.prepareStoresForLoad(container: new, model: model)
        try load(new)
        let context = new.viewContext
        let request = NSFetchRequest<NSManagedObject>(entityName: "LessonAttachment")
        request.affectedStores = [try privateStore(of: new)]
        let rows = try context.fetch(request)

        // 3. The file is still there, with no modifiedAt; it reads as attached.
        #expect(rows.count == 1)
        let row = try #require(rows.first)
        #expect(row.value(forKey: "id") as? UUID == id)
        #expect(row.value(forKey: "fileName") as? String == "Area of a Circle.pdf")
        #expect(row.value(forKey: "attachedAt") as? Date == Self.attached)
        #expect(row.value(forKey: "modifiedAt") == nil)
        #expect((row as? CDLessonAttachment)?.lastChanged == Self.attached)

        // 4. And it takes one.
        row.setValue(Self.changed, forKey: "modifiedAt")
        try context.save()
        context.refresh(row, mergeChanges: false)
        #expect(row.value(forKey: "modifiedAt") as? Date == Self.changed)
    }
}
