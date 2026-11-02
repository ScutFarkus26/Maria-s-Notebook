import Foundation
import Testing
@testable import CosmicDaybook

// MARK: - Backup Preferences
//
// The preferences entry is the one part of a backup that isn't a Core Data
// row. These tests pin the value conversions (so a 0/1 integer never comes
// back as a Bool, and list/map preferences survive), the merge policies for
// device-keyed album state, and the Codable shape of the new `plist` case.

@Suite("Backup preferences")
struct BackupPreferencesServiceTests {

    @Test("Scalar preference values convert to DTOs and back without changing type")
    func scalarRoundTrip() throws {
        let cases: [(Any, PreferenceValueDTO)] = [
            (true, .bool(true)),
            (false, .bool(false)),
            (1, .int(1)),
            (0, .int(0)),
            (90, .int(90)),
            (0.3, .double(0.3)),
            ("standard", .string("standard")),
            (Date(timeIntervalSinceReferenceDate: 1_000), .date(Date(timeIntervalSinceReferenceDate: 1_000)))
        ]
        for (stored, expected) in cases {
            // Route through NSNumber the way UserDefaults hands values back.
            let object: Any = (stored as? Bool).map { NSNumber(value: $0) }
                ?? (stored as? Int).map { NSNumber(value: $0) }
                ?? (stored as? Double).map { NSNumber(value: $0) }
                ?? stored
            let dto = try #require(BackupPreferencesService.dtoValue(for: object))
            #expect(dto == expected, "\(stored) → \(dto)")
            let back = try #require(BackupPreferencesService.nativeValue(for: dto))
            #expect(BackupPreferencesService.dtoValue(for: back) == expected)
        }
    }

    @Test("List and map preferences round-trip through the plist case")
    func collectionRoundTrip() throws {
        let tagOrder = ["math", "language", "cosmic"]
        let dto = try #require(BackupPreferencesService.dtoValue(for: tagOrder))
        guard case .plist = dto else {
            Issue.record("expected .plist, got \(dto)")
            return
        }
        #expect(BackupPreferencesService.nativeValue(for: dto) as? [String] == tagOrder)

        let fingerprints = ["abc": "Biology Album.pdf", "def": "Geometry Album.pdf"]
        let mapDTO = try #require(BackupPreferencesService.dtoValue(for: fingerprints))
        #expect(BackupPreferencesService.nativeValue(for: mapDTO) as? [String: String] == fingerprints)

        let bookmarks = [Data([1, 2, 3]), Data([4, 5])]
        let dataDTO = try #require(BackupPreferencesService.dtoValue(for: bookmarks))
        #expect(BackupPreferencesService.nativeValue(for: dataDTO) as? [Data] == bookmarks)
    }

    @Test("plist values survive JSON encoding like the archive's preferences.json")
    func plistCodable() throws {
        let original = PreferencesDTO(values: [
            "Todo.tagOrder": try #require(BackupPreferencesService.dtoValue(for: ["a", "b"])),
            "Recall.spacedIntervalDays": .int(90)
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PreferencesDTO.self, from: data)
        #expect(decoded.values == original.values)
        let tagOrder = try #require(decoded.values["Todo.tagOrder"])
        #expect(BackupPreferencesService.nativeValue(for: tagOrder) as? [String] == ["a", "b"])
    }

    @Test("Album folder bookmarks union with the device's own list")
    func bookmarkUnion() {
        let local: [Data] = [Data([1]), Data([2])]
        let restored: [Data] = [Data([2]), Data([3])]
        let merged = BackupPreferencesService.merge(restored: restored, local: local, policy: .unionArray) as? [Data]
        #expect(merged == [Data([1]), Data([2]), Data([3])])

        let fresh = BackupPreferencesService.merge(restored: restored, local: nil, policy: .unionArray) as? [Data]
        #expect(fresh == restored)
    }

    @Test("Album fingerprint map keeps local entries and fills gaps from the backup")
    func fingerprintMerge() {
        let local = ["print-a": "Biology (renamed).pdf"]
        let restored = ["print-a": "Biology.pdf", "print-b": "Geometry.pdf"]
        let merged = BackupPreferencesService.merge(
            restored: restored, local: local, policy: .mergeDictionaryLocalWins
        ) as? [String: String]
        #expect(merged == ["print-a": "Biology (renamed).pdf", "print-b": "Geometry.pdf"])
    }

    @Test("Merge policies are wired to the album keys and Claude's attach folders, and nothing else")
    func mergePolicyWiring() {
        #expect(BackupPreferencesService.mergePolicy(for: UserDefaultsKeys.albumsFolderBookmarks) == .unionArray)
        for key in [UserDefaultsKeys.albumsFingerprints, UserDefaultsKeys.albumsLastSeenModDates] {
            #expect(BackupPreferencesService.mergePolicy(for: key) == .mergeDictionaryLocalWins, "\(key)")
        }
        #expect(BackupPreferencesService.mergePolicy(for: UserDefaultsKeys.aiMCPAttachFolderBookmarks) == .unionArray)
        for key in BackupPreferencesService.preferenceKeys
        where !key.hasPrefix("Albums.") && key != UserDefaultsKeys.aiMCPAttachFolderBookmarks {
            #expect(BackupPreferencesService.mergePolicy(for: key) == .replace, "\(key)")
        }
    }

    @Test("Preference key list has no duplicates and covers the settings that change how data reads")
    func keyListShape() {
        let keys = BackupPreferencesService.preferenceKeys
        #expect(keys.count == Set(keys).count, "duplicate keys: \(keys)")
        let mustHave = [
            UserDefaultsKeys.schoolYearStartMonth,
            UserDefaultsKeys.schoolYearStartDay,
            UserDefaultsKeys.schoolYearSelection,
            UserDefaultsKeys.schoolYearCountersResetAtYearStart,
            UserDefaultsKeys.recallSpacedIntervalDays,
            UserDefaultsKeys.generalTestStudentNames,
            UserDefaultsKeys.lessonPlanningSystemPrompt,
            UserDefaultsKeys.albumsFingerprints,
            UserDefaultsKeys.aiMCPAttachFolderBookmarks,
            "AttendanceEmail.nameOrder"
        ]
        for key in mustHave {
            #expect(keys.contains(key), "missing \(key)")
        }
        // Never export secrets or device-only plumbing.
        let forbidden = [
            UserDefaultsKeys.cloudKitLastErrorDescription,
            UserDefaultsKeys.persistentHistoryStoreTokens,
            UserDefaultsKeys.classroomSharePendingAttach,
            UserDefaultsKeys.aiMCPServerEnabled,
            UserDefaultsKeys.classroomIdentityRecordName,
            UserDefaultsKeys.resetLocalCacheOnLaunch
        ]
        for key in forbidden {
            #expect(!keys.contains(key), "must not export \(key)")
        }
        #expect(BackupPreferencesService.preferenceKeyPrefixes == ["Attendance.locked."])
    }

    @Test("The Scheduled pane's settings are no longer backed up, and an old backup carrying them still restores")
    func scheduledPaneKeysRetired() throws {
        // Open or closed, its height, and which kinds it showed: nothing reads
        // them since the pane went on hold (2026-11-01).
        let retired = ["WorkAgenda.calendarExpanded", "WorkAgenda.calendarFraction", "Calendar.visibleKinds"]
        for key in retired {
            #expect(!BackupPreferencesService.preferenceKeys.contains(key), "\(key)")
            // A restore applies only what `isBackedUp` accepts, so an old
            // backup's values for these are passed over, not an error.
            #expect(!BackupPreferencesService.isBackedUp(key), "\(key)")
        }
        // An older preferences.json carrying them still decodes whole.
        let old = PreferencesDTO(values: [
            "WorkAgenda.calendarExpanded": .bool(true),
            "WorkAgenda.calendarFraction": .double(0.42),
            "Calendar.visibleKinds": .string("everything"),
            UserDefaultsKeys.workAgendaHideScheduled: .bool(false)
        ])
        let decoded = try JSONDecoder().decode(PreferencesDTO.self, from: JSONEncoder().encode(old))
        #expect(decoded.values.count == 4)
        let restored = decoded.values.keys.filter(BackupPreferencesService.isBackedUp)
        #expect(restored == [UserDefaultsKeys.workAgendaHideScheduled])
    }
}
