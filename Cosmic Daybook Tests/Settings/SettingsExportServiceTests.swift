import Foundation
import Testing
@testable import CosmicDaybook

/// Pins "Move settings to another device": a file exported from one device
/// reproduces its settings on another, old version-1 files still import, and a
/// file can only set the settings the export carries.
///
/// Each test reads and writes its own `UserDefaults(suiteName:)` with no synced
/// store, so every key lands in that suite and nothing touches the test host's
/// settings or iCloud.
@Suite("Settings export")
@MainActor
struct SettingsExportServiceTests {

    private func makeStore() throws -> (store: UserDefaults, name: String) {
        let name = "SettingsExportServiceTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test("The export carries the school year, order requests, Private Cloud and quick capture")
    func carriesTheSettingsVersionOneMissed() {
        let keys = Set(SettingsExportService.transferKeys)
        #expect(keys.contains(UserDefaultsKeys.schoolYearStartMonth))
        #expect(keys.contains("Orders.recipientEmail"))
        #expect(keys.contains(UserDefaultsKeys.aiAllowAutomaticPrivateCloud))
        #expect(keys.contains(UserDefaultsKeys.quickCaptureButtonVisible))
        #expect(keys.contains(UserDefaultsKeys.autoBackupIntervalHours))
    }

    @Test("The export leaves out what belongs to this device")
    func leavesOutDeviceOnlyKeys() {
        let keys = Set(SettingsExportService.transferKeys)
        #expect(!keys.contains("Backup.encrypt"))
        #expect(!keys.contains("LastBackupTimeInterval"))
        #expect(!keys.contains(UserDefaultsKeys.lastBackupTimeInterval))
        #expect(!keys.contains(UserDefaultsKeys.albumsFolderBookmarks))
        #expect(!keys.contains(UserDefaultsKeys.aiMCPServerEnabled))
        #expect(keys.count == SettingsExportService.transferKeys.count, "a key is listed twice")
    }

    @Test("Export, clear, import: every setting comes back as it was")
    func roundTrip() throws {
        let (source, sourceName) = try makeStore()
        defer { source.removePersistentDomain(forName: sourceName) }
        let when = Date(timeIntervalSinceReferenceDate: 780_000_000)
        let tagOrder = ["Math", "Language", "Cosmic"]
        let untouchedByArea: [String: Int] = ["Math": 30, "Geography": 45]

        source.set(9, forKey: UserDefaultsKeys.schoolYearStartMonth)
        source.set("Ms. Rivera", forKey: "Orders.recipientName")
        source.set(true, forKey: UserDefaultsKeys.aiAllowAutomaticPrivateCloud)
        source.set(false, forKey: UserDefaultsKeys.quickCaptureButtonVisible)
        source.set(0.7, forKey: UserDefaultsKeys.lessonPlanningTemperature)
        source.set(6, forKey: UserDefaultsKeys.autoBackupIntervalHours)
        source.set(when, forKey: UserDefaultsKeys.lessonsAgendaStartDate)
        source.set(tagOrder, forKey: UserDefaultsKeys.todoTagOrder)
        source.set(untouchedByArea, forKey: UserDefaultsKeys.curriculumMapUntouchedDaysByArea)
        // Device-only: must not travel.
        source.set(123.0, forKey: "LastBackupTimeInterval")

        let data = try #require(SettingsExportService.exportSettings(defaults: source, syncedStore: nil))

        let (target, targetName) = try makeStore()
        defer { target.removePersistentDomain(forName: targetName) }
        // Chosen here but never on the exporting device: import leaves it alone.
        target.set(900, forKey: UserDefaultsKeys.lessonPlanningTimeout)
        target.set(456.0, forKey: "LastBackupTimeInterval")

        try SettingsExportService.importSettings(from: data, defaults: target, syncedStore: nil)

        #expect(target.integer(forKey: UserDefaultsKeys.schoolYearStartMonth) == 9)
        #expect(target.string(forKey: "Orders.recipientName") == "Ms. Rivera")
        #expect(target.object(forKey: UserDefaultsKeys.aiAllowAutomaticPrivateCloud) as? Bool == true)
        #expect(target.object(forKey: UserDefaultsKeys.quickCaptureButtonVisible) as? Bool == false)
        #expect(target.double(forKey: UserDefaultsKeys.lessonPlanningTemperature) == 0.7)
        #expect(target.integer(forKey: UserDefaultsKeys.autoBackupIntervalHours) == 6)
        #expect(target.object(forKey: UserDefaultsKeys.lessonsAgendaStartDate) as? Date == when)
        #expect(target.stringArray(forKey: UserDefaultsKeys.todoTagOrder) == tagOrder)
        #expect(
            target.dictionary(forKey: UserDefaultsKeys.curriculumMapUntouchedDaysByArea) as? [String: Int]
                == untouchedByArea
        )
        #expect(target.integer(forKey: UserDefaultsKeys.lessonPlanningTimeout) == 900)
        #expect(target.double(forKey: "LastBackupTimeInterval") == 456.0)
    }

    @Test("A version-1 file still imports, without the stale encrypt setting")
    func versionOneImports() throws {
        let (target, name) = try makeStore()
        defer { target.removePersistentDomain(forName: name) }
        let file: [String: Any] = [
            "exportVersion": 1,
            "exportDate": "2026-05-01T12:00:00Z",
            "appVersion": "1.0",
            "lessonAgeWarningDays": 5,
            "lessonPlanningDefaultDepth": "deep",
            "lessonPlanningTemperature": 0.4,
            "autoBackupEnabled": false,
            "autoBackupRetentionCount": 20,
            "attendanceEmailTo": "office@example.com",
            "backupEncrypt": true
        ]
        let data = try JSONSerialization.data(withJSONObject: file)

        try SettingsExportService.importSettings(from: data, defaults: target, syncedStore: nil)

        #expect(target.integer(forKey: "LessonAge.warningDays") == 5)
        #expect(target.string(forKey: UserDefaultsKeys.lessonPlanningDefaultDepth) == "deep")
        #expect(target.double(forKey: UserDefaultsKeys.lessonPlanningTemperature) == 0.4)
        #expect(target.object(forKey: UserDefaultsKeys.autoBackupEnabled) as? Bool == false)
        #expect(target.integer(forKey: UserDefaultsKeys.autoBackupRetentionCount) == 20)
        #expect(target.string(forKey: "AttendanceEmail.to") == "office@example.com")
        #expect(target.object(forKey: "Backup.encrypt") == nil)
    }

    @Test("A file can't set anything outside the exported settings")
    func ignoresUnknownKeys() throws {
        let (target, name) = try makeStore()
        defer { target.removePersistentDomain(forName: name) }
        let file: [String: Any] = [
            "exportVersion": SettingsExportService.currentVersion,
            "exportDate": "2026-09-30T12:00:00Z",
            "appVersion": "1.0",
            "settings": [
                UserDefaultsKeys.aiMCPServerEnabled: ["type": "bool", "value": true],
                UserDefaultsKeys.schoolYearStartDay: ["type": "int", "value": 15]
            ],
            "unchanged": ["LastBackupTimeInterval"]
        ]
        target.set(789.0, forKey: "LastBackupTimeInterval")
        let data = try JSONSerialization.data(withJSONObject: file)

        try SettingsExportService.importSettings(from: data, defaults: target, syncedStore: nil)

        #expect(target.integer(forKey: UserDefaultsKeys.schoolYearStartDay) == 15)
        #expect(target.object(forKey: UserDefaultsKeys.aiMCPServerEnabled) == nil)
        #expect(target.double(forKey: "LastBackupTimeInterval") == 789.0)
    }

    @Test("A newer file or a stranger's file is refused with a clear reason")
    func refusesOtherFiles() throws {
        let (target, name) = try makeStore()
        defer { target.removePersistentDomain(forName: name) }
        let newer = try JSONSerialization.data(withJSONObject: ["exportVersion": 99])
        #expect(throws: SettingsExportService.SettingsImportError.incompatibleVersion) {
            try SettingsExportService.importSettings(from: newer, defaults: target, syncedStore: nil)
        }
        let stranger = try JSONSerialization.data(withJSONObject: ["name": "grocery list"])
        #expect(throws: SettingsExportService.SettingsImportError.invalidFormat) {
            try SettingsExportService.importSettings(from: stranger, defaults: target, syncedStore: nil)
        }
    }
}
