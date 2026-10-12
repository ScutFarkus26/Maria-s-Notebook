import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-10-11, #65. Uniform check-in work was saved naming its
// project check-in (`sourceContextID`) without the type every project reader
// filters on. A one-time repair per device stamps the type on exactly that
// work: an empty type and a context id that is a project check-in's id. It
// waits for the first download, saves its own change, and only fills an
// empty field, so two devices running it converge.

@Suite("Project check-in work repair (Fix1011P)")
@MainActor
struct ProjectWorkContextRepairTests {

    private func isolatedDefaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "ProjectWorkContextRepairTests.\(UUID().uuidString)"))
    }

    /// Uniform work as the old sheet left it, choice work already typed, a
    /// presentation's work, a context id naming no check-in, and plain work.
    private struct Seeded {
        let untyped: [CDWorkModel]
        let typedChoice: CDWorkModel
        let presentationWork: CDWorkModel
        let unknownContext: CDWorkModel
        let plain: CDWorkModel
    }

    private func seed(_ context: NSManagedObjectContext) -> Seeded {
        let project = CDProject(context: context)
        project.title = "Bridges"
        let session = CDProjectSession(context: context)
        session.projectID = project.id?.uuidString ?? ""
        project.addToSessions(session)
        let sessionID = session.id?.uuidString ?? ""

        let untyped = (0..<2).map { index in
            let work = CoreDataTestHelpers.seedWorkModel(in: context, title: "Bridges: Follow-Up \(index)")
            work.sourceContextID = sessionID
            return work
        }
        let typedChoice = CoreDataTestHelpers.seedWorkModel(in: context, title: "Build a truss")
        typedChoice.sourceContextType = .projectSession
        typedChoice.sourceContextID = sessionID
        let presentationWork = CoreDataTestHelpers.seedWorkModel(in: context, title: "Practice the bead chain")
        presentationWork.sourceContextType = .presentation
        presentationWork.sourceContextID = UUID().uuidString
        let unknownContext = CoreDataTestHelpers.seedWorkModel(in: context, title: "Orphan")
        unknownContext.sourceContextID = UUID().uuidString
        let plain = CoreDataTestHelpers.seedWorkModel(in: context, title: "Plain work")
        return Seeded(
            untyped: untyped,
            typedChoice: typedChoice,
            presentationWork: presentationWork,
            unknownContext: unknownContext,
            plain: plain
        )
    }

    @Test("Stamps the type on untyped work that names a project check-in, and nothing else")
    func repairsOnlyProjectWork() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let seeded = seed(context)
        #expect(CoreDataTestHelpers.save(context))

        let changed = DataCleanupService.repairProjectWorkContextType(using: context)
        #expect(changed == 2)
        for work in seeded.untyped {
            #expect(work.sourceContextType == .projectSession)
        }
        #expect(seeded.typedChoice.sourceContextType == .projectSession)
        #expect(seeded.presentationWork.sourceContextType == .presentation)
        #expect(seeded.unknownContext.sourceContextTypeRaw == nil)
        #expect(seeded.plain.sourceContextTypeRaw == nil)
        #expect(seeded.typedChoice.changedValues().isEmpty, "a typed row isn't written")
        #expect(seeded.presentationWork.changedValues().isEmpty)

        #expect(CoreDataTestHelpers.save(context))
        #expect(DataCleanupService.repairProjectWorkContextType(using: context) == 0, "a second run finds nothing")
        #expect(!context.hasChanges)
    }

    @Test("Runs once per device, saves, and then stays done")
    func runsOnce() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let defaults = try isolatedDefaults()
        let seeded = seed(context)
        #expect(CoreDataTestHelpers.save(context))

        let first = DataCleanupService.repairProjectWorkContextTypeIfDue(
            using: context, firstDownloadPending: false, defaults: defaults
        )
        #expect(first == 2)
        #expect(!context.hasChanges, "it saves its own changes")
        #expect(defaults.bool(forKey: UserDefaultsKeys.projectWorkContextRepairDone))

        seeded.untyped[0].sourceContextTypeRaw = nil
        #expect(CoreDataTestHelpers.save(context))
        let again = DataCleanupService.repairProjectWorkContextTypeIfDue(
            using: context, firstDownloadPending: false, defaults: defaults
        )
        #expect(again == nil)
    }

    @Test("While the first download is pending it waits and isn't marked done")
    func waitsForFirstDownload() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let defaults = try isolatedDefaults()
        let seeded = seed(context)
        #expect(CoreDataTestHelpers.save(context))

        let pending = DataCleanupService.repairProjectWorkContextTypeIfDue(
            using: context, firstDownloadPending: true, defaults: defaults
        )
        #expect(pending == nil)
        #expect(seeded.untyped[0].sourceContextTypeRaw == nil)
        #expect(!defaults.bool(forKey: UserDefaultsKeys.projectWorkContextRepairDone))

        let later = DataCleanupService.repairProjectWorkContextTypeIfDue(
            using: context, firstDownloadPending: false, defaults: defaults
        )
        #expect(later == 2)
    }

    @Test("A pass whose earlier steps left unsaved changes doesn't run it")
    func skipsWithLeftoverChanges() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let defaults = try isolatedDefaults()
        let seeded = seed(context)
        #expect(CoreDataTestHelpers.save(context))
        CoreDataTestHelpers.seedNote(in: context, body: "Left unsaved by an earlier step.")

        let result = DataCleanupService.repairProjectWorkContextTypeIfDue(
            using: context, firstDownloadPending: false, defaults: defaults
        )
        #expect(result == nil)
        #expect(seeded.untyped[0].sourceContextTypeRaw == nil)
        #expect(!defaults.bool(forKey: UserDefaultsKeys.projectWorkContextRepairDone))
    }

    @Test("Reset Local Cache forgets the repair ran, so a fresh download is checked again")
    func resetLocalCacheClearsFlag() throws {
        let defaults = try isolatedDefaults()
        defaults.set(true, forKey: UserDefaultsKeys.projectWorkContextRepairDone)
        CoreDataStack.clearLocalCacheResetFlags(in: defaults)
        #expect(!defaults.bool(forKey: UserDefaultsKeys.projectWorkContextRepairDone))
    }

    @Test("On a background context, as the launch pass runs it, the view context sees the type")
    func backgroundContextRun() async throws {
        let stack = try CoreDataTestHelpers.makeInMemoryStack()
        let seeded = seed(stack.viewContext)
        #expect(CoreDataTestHelpers.save(stack.viewContext))
        let suiteName = "ProjectWorkContextRepairTests.\(UUID().uuidString)"

        let background = stack.newBackgroundContext()
        let changed: Int? = await background.perform {
            guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
            return DataCleanupService.repairProjectWorkContextTypeIfDue(
                using: background, firstDownloadPending: false, defaults: defaults
            )
        }
        #expect(changed == 2)
        stack.viewContext.refreshAllObjects()
        #expect(seeded.untyped.allSatisfy { $0.sourceContextType == .projectSession })
    }
}
