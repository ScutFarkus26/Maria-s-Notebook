import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

/// Round-two Simplify, Phase 4: the seeder makes the two built-in meeting
/// templates and nothing else. Note templates were retired: the entity stays
/// in the model with no class, and rows a store already holds stay put.
@Suite("Built-in template seeder")
@MainActor
struct BuiltInTemplateSeederTests {

    private func freshDefaults() throws -> (UserDefaults, String) {
        let suiteName = "BuiltInTemplateSeederTests-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suiteName)), suiteName)
    }

    private func count(_ entityName: String, in context: NSManagedObjectContext) throws -> Int {
        try context.count(for: NSFetchRequest<NSFetchRequestResult>(entityName: entityName))
    }

    @Test("An empty notebook gets the two meeting templates and no note templates")
    func seedsMeetingTemplatesOnly() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (defaults, suiteName) = try freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        BuiltInTemplateSeeder.seedIfNeeded(context: context, defaults: defaults)

        let meetings = context.safeFetch(CDFetchRequest(CDMeetingTemplate.self))
        let names = Set(meetings.map(\.name))
        #expect(names == ["Standard Student Meeting", "Quick Check-In"])
        let allBuiltIn = meetings.allSatisfy { $0.isBuiltIn }
        #expect(allBuiltIn)
        let noteTemplateCount = try count("NoteTemplate", in: context)
        #expect(noteTemplateCount == 0)
    }

    @Test("A second run adds nothing")
    func secondRunAddsNothing() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (defaults, suiteName) = try freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }

        BuiltInTemplateSeeder.seedIfNeeded(context: context, defaults: defaults)
        BuiltInTemplateSeeder.seedIfNeeded(context: context, defaults: defaults)

        let meetingTemplateCount = try count("MeetingTemplate", in: context)
        #expect(meetingTemplateCount == 2)
    }

    @Test("Nothing is seeded while the first download from iCloud is under way")
    func waitsForFirstDownload() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (defaults, suiteName) = try freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: FirstDownloadGate.key)
        try #require(FirstDownloadGate.isPending(defaults: defaults))

        BuiltInTemplateSeeder.seedIfNeeded(context: context, defaults: defaults)

        let meetingTemplateCount = try count("MeetingTemplate", in: context)
        #expect(meetingTemplateCount == 0)
    }

    @Test("Note templates a store already holds stay, as plain rows with no class")
    func retiredNoteTemplatesStay() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let (defaults, suiteName) = try freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: suiteName) }
        let entity = try #require(
            context.persistentStoreCoordinator?.managedObjectModel.entitiesByName["NoteTemplate"]
        )
        #expect(entity.managedObjectClassName == NSStringFromClass(NSManagedObject.self))
        let old = NSManagedObject(entity: entity, insertInto: context)
        old.setValue(UUID(), forKey: "id")
        old.setValue("Observation", forKey: "title")
        old.setValue(true, forKey: "isBuiltIn")
        #expect(CoreDataTestHelpers.save(context))

        BuiltInTemplateSeeder.seedIfNeeded(context: context, defaults: defaults)

        let noteTemplateCount = try count("NoteTemplate", in: context)
        #expect(noteTemplateCount == 1)
        let meetingTemplateCount = try count("MeetingTemplate", in: context)
        #expect(meetingTemplateCount == 2)
    }
}
