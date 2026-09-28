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

    @Test("The test host is a Development build")
    func testHostIsDevelopment() {
        #expect(CloudKitEnvironment.current == .development)
        #expect(Bundle.main.object(forInfoDictionaryKey: CloudKitEnvironment.infoPlistKey) as? String == "Development")
        #expect(CloudKitEnvironment.allowsSchemaInitialization)
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

    @Test("Per-store sync keys keep their Development names")
    func developmentKeyNamesUnchanged() {
        #expect(UserDefaultsKeys.persistentHistoryStoreTokens == "PersistentHistory.storeTokens")
        #expect(UserDefaultsKeys.firstDownloadPending == "CloudKit.firstDownloadPending")
        #expect(UserDefaultsKeys.cloudKitLastSuccessfulExportStartDate == "CloudKitSync.lastSuccessfulExportStartDate")
        #expect(UserDefaultsKeys.persistentHistoryLastPurgeDate == "PersistentHistory.lastPurgeDate")
        #expect(UserDefaultsKeys.cloudKitLastSuccessfulSyncDate == "CloudKitSync.lastSuccessfulSyncDate")
        #expect(UserDefaultsKeys.checkInLinkRepairHasRun == "DataMigrations.checkInLinkRepair.hasRun")
        #expect(UserDefaultsKeys.classroomIdentityRecordName == "ClassroomIdentity.userRecordName")
        #expect(UserDefaultsKeys.cloudKitErrorLog == "cloudKitErrorLog")
    }

    @Test("Production's notebook lives in its own folder; Development's and Sample Class stay put")
    func storeFolders() {
        let base = CoreDataStack.baseStoreDirectory()
        #expect(CoreDataStack.storeDirectory(environment: .development) == base)
        let production = CoreDataStack.storeDirectory(environment: .production)
        #expect(production == base.appendingPathComponent("Production", isDirectory: true))
        #expect(production.standardizedFileURL != base.standardizedFileURL)
        #expect(CoreDataStack.privateStoreURL().deletingLastPathComponent().standardizedFileURL
            == base.standardizedFileURL)
        #expect(CoreDataStack.sampleClassroomStoreURL().deletingLastPathComponent().standardizedFileURL
            == base.standardizedFileURL)
    }
}
