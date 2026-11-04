import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Bug hunt 2026-11-02, #7 and #57. (#59, the lesson name merge and track
// steps, went with the track entities at schema 23.)
//
// #7: restore set a project session's `projectID` but never its project, so
// restored sessions vanished from their book club or project; the launch now
// links those an older restore left.
// #57: a safe-mode launch (the stores didn't open; an empty store in memory)
// ran the one-time launch steps and marked them done for good.

@Suite("Launch repairs: sessions relinked, safe mode (hunt 11-02)")
@MainActor
struct LaunchRepairsHunt1102Tests {

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "LaunchRepairsHunt1102Tests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suiteName)), suiteName)
    }

    // MARK: - #7

    @Test("A session naming its project but not linked to it is linked; one naming no project here is left")
    func unlinkedSessionsAreRelinked() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let project = CDProject(context: context)
        project.title = "Book club"
        let projectID = try #require(project.id)
        let restored = CDProjectSession(context: context)
        restored.projectID = projectID.uuidString
        let elsewhere = CDProjectSession(context: context)
        elsewhere.projectID = UUID().uuidString
        let loose = CDProjectSession(context: context)
        loose.projectID = ""
        #expect(CoreDataTestHelpers.save(context))
        #expect(restored.project == nil)

        let linked = DataCleanupService.relinkUnlinkedProjectSessionsIfDue(using: context, firstDownloadPending: false)

        #expect(linked == 1)
        #expect(restored.project == project)
        #expect(elsewhere.project == nil)
        #expect(loose.project == nil)
        #expect(!context.hasChanges, "it saves what it linked")
        #expect(DataCleanupService.relinkUnlinkedProjectSessionsIfDue(using: context, firstDownloadPending: false) == 0)
    }

    @Test("Nothing is linked while the first download runs, or over changes not yet saved")
    func relinkWaitsForTheDownloadAndUnsavedChanges() throws {
        let context = try CoreDataTestHelpers.makeContext()
        let project = CDProject(context: context)
        let session = CDProjectSession(context: context)
        session.projectID = try #require(project.id).uuidString
        #expect(CoreDataTestHelpers.save(context))

        let relink = { (pending: Bool) in
            DataCleanupService.relinkUnlinkedProjectSessionsIfDue(using: context, firstDownloadPending: pending)
        }
        #expect(relink(true) == nil)
        project.title = "Being typed"
        #expect(relink(false) == nil)
        #expect(session.project == nil)
    }

    // MARK: - #57

    @Test("In a session on the temporary in-memory store the launch steps don't run or set their flags")
    func safeModeRunsNoLaunchSteps() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(true, forKey: UserDefaultsKeys.inMemoryStoreSession)
        let flag = "LaunchRepairsHunt1102Tests.stepDone"
        let context = try CoreDataTestHelpers.makeContext()
        var ran = false

        let saved = AppBootstrapper.runLaunchBatch(in: context, oneShotFlags: [flag], defaults: defaults) {
            ran = true
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Dee")
            defaults.set(true, forKey: flag)
        }

        #expect(!saved)
        #expect(!ran)
        #expect(!defaults.bool(forKey: flag))
        #expect(!context.hasChanges)

        // The next launch that opens the stores runs them.
        defaults.set(false, forKey: UserDefaultsKeys.inMemoryStoreSession)
        #expect(AppBootstrapper.runLaunchBatch(in: context, oneShotFlags: [flag], defaults: defaults) {
            ran = true
            defaults.set(true, forKey: flag)
        })
        #expect(ran)
        #expect(defaults.bool(forKey: flag))
    }
}
