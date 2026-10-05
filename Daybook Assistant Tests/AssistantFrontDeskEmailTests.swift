import Foundation
import CoreData
import Testing
@testable import Daybook_Assistant

// The front-desk email as the assistant sends it: a child who came late and
// then left is listed once, and the guide's settings and the day's sends come
// from the classroom share only.
@Suite("Assistant front-desk email")
@MainActor
struct AssistantFrontDeskEmailTests {

    private let today = Calendar.current.startOfDay(for: Date())

    private static let settings = AttendanceEmailLog.Settings(
        isEnabled: true, toAddresses: "office@school.org", nameOrder: .firstLast, groupByLevel: false
    )

    @Test("A child who arrived late and then left early is under Left Early, marked as late, and not under Tardy")
    func lateThenLeftEarly() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let maya = AssistantTestSupport.student("Maya", "Stone", in: context)
        let bo = AssistantTestSupport.student("Bo", "Adams", in: context)
        let ada = AssistantTestSupport.student("Ada", "Zeller", in: context)
        AttendanceEmailLog.saveSettings(Self.settings, role: .leadGuide, in: context)
        let store = CDAttendanceStore(context: context, role: .assistant)
        let late = try #require(try store.ensureRecord(for: bo, on: today))
        store.updateStatus(late, to: .tardy)
        store.updateStatus(late, to: .leftEarly)
        let onTime = try #require(try store.ensureRecord(for: ada, on: today))
        store.updateStatus(onTime, to: .present)
        store.updateStatus(onTime, to: .leftEarly)
        let here = try #require(try store.ensureRecord(for: maya, on: today))
        store.updateStatus(here, to: .present)
        #expect(context.safeSave())

        let model = AssistantTestSupport.viewModel(stack)
        let body = try #require(model.frontDesk.draft(for: model.rows)).body
        let lines = body.components(separatedBy: "\n")

        #expect(lines.contains("    • Bo Adams (arrived late)"))
        #expect(lines.contains("    • Ada Zeller"))
        #expect(lines.contains("LEFT EARLY (2)"))
        #expect(lines.contains("TARDY (0)"))
    }

    // MARK: - Two stores

    /// Private and shared SQLite stores in a temporary folder, as on a phone.
    private func splitContext() throws -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: try CoreDataStack.sharedModel())
        let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for configuration in [CoreDataStack.privateConfiguration, CoreDataStack.sharedConfiguration] {
            _ = try coordinator.addPersistentStore(
                type: .sqlite, configuration: configuration, at: dir.appendingPathComponent("\(configuration).sqlite")
            )
        }
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    private func store(_ configuration: String, in context: NSManagedObjectContext) throws -> NSPersistentStore {
        let stores = context.persistentStoreCoordinator?.persistentStores ?? []
        return try #require(stores.first { $0.configurationName == configuration })
    }

    @Test("The guide's settings and the day's sends come from the classroom share, not her own notebook")
    func readsTheShareOnly() throws {
        let context = try splitContext()
        let shared = try store(CoreDataStack.sharedConfiguration, in: context)
        let privateStore = try store(CoreDataStack.privateConfiguration, in: context)

        let guides = CDAttendanceEmailSettings(context: context)
        context.assign(guides, to: shared)
        guides.isEnabled = true
        guides.toAddresses = "office@school.org"
        guides.modifiedAt = today.addingTimeInterval(-86_400)
        // A notebook of her own on the same Apple Account, set up more recently.
        let own = CDAttendanceEmailSettings(context: context)
        context.assign(own, to: privateStore)
        own.isEnabled = true
        own.toAddresses = "me@home.org"
        own.modifiedAt = today
        let ownSend = CDAttendanceEmailSend(context: context)
        context.assign(ownSend, to: privateStore)
        ownSend.date = today
        ownSend.sentAt = today.addingTimeInterval(8 * 3600)
        #expect(context.safeSave())

        #expect(AttendanceEmailLog.settings(in: context)?.toAddresses == "office@school.org")
        #expect(AttendanceEmailLog.latestSend(on: today, in: context) == nil)
        #expect(AttendanceEmailLog.sends(on: today, in: context).isEmpty)

        let classSend = CDAttendanceEmailSend(context: context)
        context.assign(classSend, to: shared)
        classSend.date = today
        classSend.sentAt = today.addingTimeInterval(7 * 3600)
        #expect(context.safeSave())
        #expect(AttendanceEmailLog.latestSend(on: today, in: context)?.sentAt == classSend.sentAt)
    }

    // MARK: - Siri

    @Test("A child Siri resolves by id is named as the grid names her, never in full")
    func entitiesByIDUseGridNames() throws {
        let stack = try AssistantTestSupport.makeStack()
        let context = stack.viewContext
        let ettyG = AssistantTestSupport.student("Etty", "Green", in: context)
        AssistantTestSupport.student("Etty", "Ross", in: context)
        let ari = AssistantTestSupport.student("Ari", "Cedar", in: context)
        #expect(context.safeSave())

        let ids = try [#require(ettyG.id), #require(ari.id)]
        let entities = StudentEntityQuery.entities(for: ids, in: context)
        let names = Dictionary(uniqueKeysWithValues: entities.map { ($0.id, $0.displayName) })

        #expect(names[ids[0]] == "Etty G")
        #expect(names[ids[1]] == "Ari")
    }

    @Test("Siri's keep-alive waits for a successful upload of the classroom share, not any export")
    func exportWatchNeedsTheShareUploaded() {
        let shared = CoreDataStack.sharedConfiguration
        func ends(_ type: NSPersistentCloudKitContainer.EventType = .export, ended: Bool = true,
                  succeeded: Bool = true, inTime: Bool = true, store: String? = shared) -> Bool {
            SiriExportWatch.ends(
                type: type, ended: ended, succeeded: succeeded, startedSinceWatching: inTime, storeConfiguration: store
            )
        }
        #expect(ends())
        #expect(!ends(succeeded: false))
        #expect(!ends(store: CoreDataStack.privateConfiguration))
        #expect(!ends(store: nil))
        #expect(!ends(ended: false))
        #expect(!ends(inTime: false))
        #expect(!ends(.import))
    }
}
