import Foundation
import Testing
@testable import CosmicDaybook

/// Pins how a build's CloudKit environment reaches the device: which folder
/// its store files live in and which key names its sync state uses. The
/// Development notebook must keep today's paths and keys exactly, so going
/// back to a Development build finds it untouched.
@Suite("CloudKit environment")
struct CloudKitEnvironmentTests {

    @Test("The Info.plist value decides; anything unreadable is Development")
    func resolvesFromInfoPlist() {
        #expect(CloudKitEnvironment.resolve("Development") == .development)
        #expect(CloudKitEnvironment.resolve("Production") == .production)
        #expect(CloudKitEnvironment.resolve(nil) == .development)
        #expect(CloudKitEnvironment.resolve("") == .development)
        // An unexpanded build setting must never read as Production.
        #expect(CloudKitEnvironment.resolve("$(CLOUDKIT_ENVIRONMENT)") == .development)
        #expect(CloudKitEnvironment.resolve("production") == .development)
    }

    @Test("The project builds for Production, which refuses schema runs")
    func testHostIsProduction() {
        #expect(CloudKitEnvironment.current == .production)
        #expect(Bundle.main.object(forInfoDictionaryKey: CloudKitEnvironment.infoPlistKey) as? String == "Production")
        #expect(!CloudKitEnvironment.allowsSchemaInitialization)
    }

    @Test("Development keeps bare keys; Production suffixes them")
    func scopesKeys() {
        let key = "PersistentHistory.storeTokens"
        #expect(CloudKitEnvironment.development.scoped(key) == key)
        #expect(
            CloudKitEnvironment.production.scoped("PersistentHistory.storeTokens")
                == "PersistentHistory.storeTokens.Production"
        )
    }

    @Test("Per-store sync keys are the Development names plus a Production suffix")
    func perStoreKeyNames() {
        // The bare strings are the Development notebook's keys, which must never
        // change; this Production build reads and writes the suffixed copies.
        let keys: [(String, String)] = [
            (UserDefaultsKeys.persistentHistoryStoreTokens, "PersistentHistory.storeTokens"),
            (UserDefaultsKeys.firstDownloadPending, "CloudKit.firstDownloadPending"),
            (UserDefaultsKeys.cloudKitLastSuccessfulExportStartDate, "CloudKitSync.lastSuccessfulExportStartDate"),
            (UserDefaultsKeys.persistentHistoryLastPurgeDate, "PersistentHistory.lastPurgeDate"),
            (UserDefaultsKeys.cloudKitLastSuccessfulSyncDate, "CloudKitSync.lastSuccessfulSyncDate"),
            (UserDefaultsKeys.checkInLinkRepairHasRun, "DataMigrations.checkInLinkRepair.hasRun"),
            (UserDefaultsKeys.classroomIdentityRecordName, "ClassroomIdentity.userRecordName"),
            (UserDefaultsKeys.cloudKitErrorLog, "cloudKitErrorLog"),
        ]
        for (key, developmentName) in keys {
            #expect(key == "\(developmentName).Production")
            #expect(CloudKitEnvironment.development.scoped(developmentName) == developmentName)
        }
    }

    @Test("Production's notebook lives in its own folder; Development's and Sample Class stay put")
    func storeFolders() {
        let base = CoreDataStack.baseStoreDirectory()
        #expect(CoreDataStack.storeDirectory(environment: .development) == base)
        let production = CoreDataStack.storeDirectory(environment: .production)
        #expect(production == base.appendingPathComponent("Production", isDirectory: true))
        #expect(production.standardizedFileURL != base.standardizedFileURL)
        #expect(CoreDataStack.privateStoreURL().deletingLastPathComponent().standardizedFileURL
            == production.standardizedFileURL)
        #expect(CoreDataStack.sampleClassroomStoreURL().deletingLastPathComponent().standardizedFileURL
            == base.standardizedFileURL)
    }
}
