import CoreData
import Foundation
import Testing
@testable import CosmicDaybook

// Data model hunt 2026-10-05, #51. The launch's one-time steps on the view
// context (old attendance locks, Restock levels, the email settings) set
// their done flags as they ran, then saved as one batch. When that save
// failed the flags stayed set, so the steps never ran again, and the rows
// they added stayed in the view context, failing every later save there.
// Now the flags are set only after the save goes through, and a failed save
// undoes only what the steps changed, keeping the guide's unsaved edits.

@Suite("The launch batch saves its steps' changes or undoes only them")
@MainActor
struct LaunchBatchSaveTests {
    private static let flag = "LaunchBatchSaveTests.stepDone"

    private func isolatedDefaults() throws -> (UserDefaults, String) {
        let suiteName = "LaunchBatchSaveTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suiteName)), suiteName)
    }

    @Test("A failed save drops the steps' rows, puts back what they changed, keeps the guide's edit and the flag unset")
    func failedSaveUndoesOnlyTheSteps() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let context = try CoreDataTestHelpers.makeContext()
        let edited = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ada")
        let touched = CoreDataTestHelpers.seedStudent(in: context, firstName: "Ben")
        #expect(CoreDataTestHelpers.save(context))
        // The guide is mid-edit when the launch steps run.
        edited.firstName = "Adah"

        let saved = AppBootstrapper.runLaunchBatch(in: context, oneShotFlags: [Self.flag], defaults: defaults) {
            touched.firstName = "Benjamin"
            // A row that can't be saved: a required value missing.
            CDWorkCheckIn(context: context).setValue(nil, forKey: "workID")
            defaults.set(true, forKey: Self.flag)
        }

        #expect(!saved)
        #expect(!defaults.bool(forKey: Self.flag))
        #expect(context.insertedObjects.isEmpty)
        #expect(touched.firstName == "Ben")
        #expect(edited.firstName == "Adah")
        // Nothing of the steps is left to fail the guide's next save.
        #expect(CoreDataTestHelpers.save(context))
    }

    @Test("A save that goes through keeps the steps' rows and sets their flags")
    func savedBatchSetsFlags() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let context = try CoreDataTestHelpers.makeContext()

        let saved = AppBootstrapper.runLaunchBatch(in: context, oneShotFlags: [Self.flag], defaults: defaults) {
            CoreDataTestHelpers.seedStudent(in: context, firstName: "Cy")
            defaults.set(true, forKey: Self.flag)
        }

        #expect(saved)
        #expect(defaults.bool(forKey: Self.flag))
        #expect(!context.hasChanges)
        #expect(context.safeFetch(CDFetchRequest(CDStudent.self)).map(\.firstName) == ["Cy"])
    }

    @Test("Steps that change nothing still count as done")
    func emptyBatchSetsFlags() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let context = try CoreDataTestHelpers.makeContext()

        let saved = AppBootstrapper.runLaunchBatch(in: context, oneShotFlags: [Self.flag], defaults: defaults) {
            defaults.set(true, forKey: Self.flag)
        }

        #expect(saved)
        #expect(defaults.bool(forKey: Self.flag))
    }
}
