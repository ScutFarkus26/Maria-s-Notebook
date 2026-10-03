import Foundation
import Testing
@testable import CosmicDaybook

/// `SchoolYearSync`: one school year on every device, with iCloud as a dictionary and each
/// test's own UserDefaults suite, so nothing reaches the machine's iCloud or real defaults.
@Suite("School year sync")
@MainActor
struct SchoolYearSyncTests {

    final class FakeCloud: SchoolYearCloudStore {
        var values: [String: Any] = [:]
        var synchronizeCount = 0
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
        func synchronize() -> Bool { synchronizeCount += 1; return true }
    }

    private let month = UserDefaultsKeys.schoolYearStartMonth
    private let day = UserDefaultsKeys.schoolYearStartDay
    private let mode = UserDefaultsKeys.schoolYearCountersResetAtYearStart

    private func freshDefaults() -> UserDefaults {
        let name = "SchoolYearSyncTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test("The Mac fills an empty iCloud with its own start date and mode")
    func macSeedsEmptyCloud() {
        let cloud = FakeCloud()
        let defaults = freshDefaults()
        defaults.set(8, forKey: month)
        defaults.set(25, forKey: day)
        defaults.set(1.0, forKey: UserDefaultsKeys.schoolYearCounterEpoch) // legacy "reset"

        let outcome = SchoolYearSync(cloud: cloud, defaults: defaults, seedsEmptyCloud: true).adoptOrSeed()

        #expect(outcome == .seeded)
        #expect(cloud.values[month] as? Int == 8)
        #expect(cloud.values[day] as? Int == 25)
        #expect(cloud.values[mode] as? Bool == true)
    }

    @Test("A new or reinstalled Mac with no start date of its own never fills iCloud with Sept 1")
    func freshMacWaitsForCloud() {
        let cloud = FakeCloud() // key-value storage not downloaded yet: looks empty
        let defaults = freshDefaults()
        let sync = SchoolYearSync(cloud: cloud, defaults: defaults, seedsEmptyCloud: true)

        #expect(sync.adoptOrSeed() == .waiting)
        #expect(cloud.values.isEmpty)

        // The class's start arrives from iCloud, and this Mac takes it.
        cloud.values = [month: 8, day: 25, mode: true]
        #expect(sync.adoptFromCloud())
        #expect(defaults.integer(forKey: month) == 8)
        #expect(defaults.integer(forKey: day) == 25)
    }

    @Test("Publishing the local settings sends only values set here, never the defaults")
    func publishLocalSendsOnlySetValues() {
        let cloud = FakeCloud()
        let defaults = freshDefaults()
        let sync = SchoolYearSync(cloud: cloud, defaults: defaults, seedsEmptyCloud: true)
        sync.publishLocalSettings()
        #expect(cloud.values.isEmpty)

        defaults.set(false, forKey: mode)
        sync.publishLocalSettings()
        #expect(cloud.values.count == 1)
        #expect(cloud.values[mode] as? Bool == false)
    }

    @Test("An iPhone never fills an empty iCloud — its stale Sept 1 can't beat the Mac")
    func phoneWaitsOnEmptyCloud() {
        let cloud = FakeCloud()
        let defaults = freshDefaults()
        defaults.set(9, forKey: month)
        defaults.set(1, forKey: day)

        let outcome = SchoolYearSync(cloud: cloud, defaults: defaults, seedsEmptyCloud: false).adoptOrSeed()

        #expect(outcome == .waiting)
        #expect(cloud.values.isEmpty)
        #expect(defaults.integer(forKey: month) == 9) // local stands until the Mac's arrives
    }

    @Test("Once iCloud holds a start date, every device adopts it — the Mac too")
    func everyoneAdoptsCloud() {
        for seeds in [true, false] {
            let cloud = FakeCloud()
            cloud.values = [month: 8, day: 25, mode: true]
            let defaults = freshDefaults()
            defaults.set(9, forKey: month)
            defaults.set(1, forKey: day)
            defaults.set(false, forKey: mode)

            let outcome = SchoolYearSync(cloud: cloud, defaults: defaults, seedsEmptyCloud: seeds).adoptOrSeed()

            #expect(outcome == .adopted(changed: true))
            #expect(defaults.integer(forKey: month) == 8)
            #expect(defaults.integer(forKey: day) == 25)
            #expect(defaults.bool(forKey: mode))
            #expect(cloud.values[month] as? Int == 8) // nothing published over it
        }
    }

    @Test("Adopting what's already local changes nothing and posts nothing")
    func adoptNoChange() {
        let cloud = FakeCloud()
        cloud.values = [month: 8, day: 25, mode: true]
        let defaults = freshDefaults()
        defaults.set(8, forKey: month)
        defaults.set(25, forKey: day)
        defaults.set(true, forKey: mode)

        let sync = SchoolYearSync(cloud: cloud, defaults: defaults, seedsEmptyCloud: false)
        #expect(sync.adoptOrSeed() == .adopted(changed: false))
    }

    @Test("A start date in iCloud without the mode: the Mac adds its mode and keeps the date")
    func macAddsMissingMode() {
        let cloud = FakeCloud()
        cloud.values = [month: 8, day: 25]
        let defaults = freshDefaults()
        defaults.set(false, forKey: mode)

        _ = SchoolYearSync(cloud: cloud, defaults: defaults, seedsEmptyCloud: true).adoptOrSeed()

        #expect(cloud.values[mode] as? Bool == false)
        #expect(cloud.values[month] as? Int == 8)
        #expect(defaults.integer(forKey: month) == 8)
    }

    @Test("Invalid values in iCloud are ignored, never copied")
    func invalidCloudValuesIgnored() {
        let cloud = FakeCloud()
        cloud.values = [month: 13, day: 25]
        let defaults = freshDefaults()
        defaults.set(9, forKey: month)

        let outcome = SchoolYearSync(cloud: cloud, defaults: defaults, seedsEmptyCloud: false).adoptOrSeed()

        #expect(outcome == .waiting)
        #expect(defaults.integer(forKey: month) == 9)
    }

    @Test("Publishing sends all three values together")
    func publishSendsAll() {
        let cloud = FakeCloud()
        let sync = SchoolYearSync(cloud: cloud, defaults: freshDefaults(), seedsEmptyCloud: false)
        sync.publish(month: 8, day: 25, resetting: false)
        #expect(cloud.values[month] as? Int == 8)
        #expect(cloud.values[day] as? Int == 25)
        #expect(cloud.values[mode] as? Bool == false)
        #expect(cloud.synchronizeCount == 1)
    }

    @Test("Under unit tests the app's instance never starts, so nothing reaches real iCloud")
    func noSharedInstanceUnderTests() {
        SchoolYearSync.start()
        #expect(SchoolYearSync.shared == nil)
    }

    @Test("A restore of an old backup maps its stored epoch to the reset mode")
    func oldBackupEpochMapsToMode() {
        let defaults = freshDefaults()
        let dto = PreferencesDTO(values: [
            UserDefaultsKeys.schoolYearCounterEpoch: .double(1.0),
            month: .int(8)
        ])
        BackupPreferencesService.applySchoolYearSettings(from: dto, defaults: defaults)
        #expect(defaults.object(forKey: mode) as? Bool == true)

        let newer = freshDefaults()
        let newDTO = PreferencesDTO(values: [mode: .bool(false), UserDefaultsKeys.schoolYearCounterEpoch: .double(1.0)])
        BackupPreferencesService.applySchoolYearSettings(from: newDTO, defaults: newer)
        #expect(newer.object(forKey: mode) == nil) // the backup's own mode is applied by the key loop
    }
}
