import Foundation

// MARK: - Backup Preferences Service

/// Service responsible for exporting and importing user preferences in backups.
///
/// Every key listed here is a setting the guide chose deliberately and would
/// expect to find intact after restoring onto a fresh device. Device-local
/// state (window positions, CloudKit tokens, migration flags, the MCP server
/// toggle, the backup destination itself) stays out on purpose.
nonisolated enum BackupPreferencesService {

    // MARK: - Preference Keys

    /// Exact keys included in backups.
    static let preferenceKeys: [String] = [
        // School year — changes how every date in the notebook is bucketed.
        UserDefaultsKeys.schoolYearStartMonth,
        UserDefaultsKeys.schoolYearStartDay,
        UserDefaultsKeys.schoolYearSelection,
        UserDefaultsKeys.schoolYearCountersResetAtYearStart,
        UserDefaultsKeys.schoolYearCounterPromptAnsweredYear,
        // Recall
        UserDefaultsKeys.recallSpacedIntervalDays,
        // Three-Year View
        UserDefaultsKeys.curriculumMapUntouchedDays,
        UserDefaultsKeys.curriculumMapUntouchedDaysByArea,
        UserDefaultsKeys.curriculumMapZoom,
        UserDefaultsKeys.curriculumMapGranularity,
        // General
        UserDefaultsKeys.generalShowTestStudents,
        UserDefaultsKeys.generalTestStudentNames,
        UserDefaultsKeys.quickCaptureButtonVisible,
        // Attendance (synced)
        "AttendanceEmail.enabled",
        "AttendanceEmail.to",
        "AttendanceEmail.from",
        "AttendanceEmail.nameOrder",
        "AttendanceEmail.groupByLevel",
        "AttendanceEmail.deadlineMinutes",
        "Attendance.sortKey",
        "Attendance.groupsByLevel",
        // Order requests (synced)
        "Orders.recipientName",
        "Orders.recipientEmail",
        "Orders.signOffName",
        "Orders.ccEmail",
        "Orders.messageTemplate",
        // Age indicators (synced)
        "LessonAge.warningDays",
        "LessonAge.overdueDays",
        "LessonAge.freshColorHex",
        "LessonAge.warningColorHex",
        "LessonAge.overdueColorHex",
        "WorkAge.warningDays",
        "WorkAge.overdueDays",
        "WorkAge.freshColorHex",
        "WorkAge.warningColorHex",
        "WorkAge.overdueColorHex",
        // Backup
        "LastBackupTimeInterval",
        UserDefaultsKeys.lastBackupTimeInterval,
        UserDefaultsKeys.autoBackupEnabled,
        UserDefaultsKeys.autoBackupRetentionCount,
        UserDefaultsKeys.autoBackupScheduledEnabled,
        UserDefaultsKeys.autoBackupIntervalHours,
        UserDefaultsKeys.backupIncludesNotePhotos,
        // AI
        UserDefaultsKeys.aiAllowAutomaticPrivateCloud,
        UserDefaultsKeys.lessonPlanningTimeout,
        UserDefaultsKeys.lessonPlanningSystemPrompt,
        UserDefaultsKeys.lessonPlanningDefaultDepth,
        UserDefaultsKeys.lessonPlanningTemperature,
        // Planning & agenda
        UserDefaultsKeys.lessonsAgendaStartDate,
        UserDefaultsKeys.lessonsAgendaMissWindow,
        UserDefaultsKeys.planningRecentWindowDays,
        UserDefaultsKeys.planningRootViewMode,
        UserDefaultsKeys.planningInboxOrder,
        UserDefaultsKeys.presentationHistoryNameDisplayStyle,
        UserDefaultsKeys.calendarVisibleKinds,
        UserDefaultsKeys.meetingsWorkflowDaysSinceThreshold,
        UserDefaultsKeys.parentReportsReminderEnabled,
        "Lessons.mapSpine",
        "PlanningCalendar.showEvents",
        "PlanningCalendar.showHolidays",
        "PlanningCalendar.showNotes",
        "PlanningCalendar.showParsha",
        "PlanningCalendar.showTodos",
        // Todos
        UserDefaultsKeys.todoTagOrder,
        UserDefaultsKeys.todoHideCompleted,
        // Work agenda & calendar
        UserDefaultsKeys.workAgendaHideScheduled,
        UserDefaultsKeys.workAgendaVisibleKinds,
        UserDefaultsKeys.workAgendaCalendarExpanded,
        UserDefaultsKeys.workAgendaCalendarFraction,
        // View preferences
        UserDefaultsKeys.studentsViewSortOrder,
        UserDefaultsKeys.studentsViewSelectedFilter,
        UserDefaultsKeys.studentPickerSortOrder,
        UserDefaultsKeys.studentDetailViewActiveTab,
        UserDefaultsKeys.checklistSelectedArea,
        UserDefaultsKeys.checklistCollapsedSequences,
        UserDefaultsKeys.logsMenuRootViewMode,
        UserDefaultsKeys.todayDayPadExpanded,
        UserDefaultsKeys.todayDoneTodayExpanded,
        UserDefaultsKeys.todayAnytimeRemindersExpanded,
        "resourceLibrary.viewMode",
        // Albums — the folder bookmarks only resolve on the device that made
        // them, but restoring them on the same Mac after a reinstall brings the
        // shelf straight back; the fingerprint map is what lets
        // AlbumIdentityRepair reattach annotations when the PDFs come back
        // under different filenames.
        UserDefaultsKeys.albumsFolderBookmarks,
        UserDefaultsKeys.albumsFingerprints,
        UserDefaultsKeys.albumsLastSeenModDates
    ]

    /// Key prefixes whose every stored key is included (per-date attendance locks).
    static let preferenceKeyPrefixes: [String] = [
        "Attendance.locked."
    ]

    private static let preferenceKeySet = Set(preferenceKeys)

    /// True for a key a backup carries and a restore applies: one of
    /// `preferenceKeys`, or one under `preferenceKeyPrefixes`. A backup can
    /// hold others (an older list's, or a hand-edited file's); a restore
    /// leaves those alone rather than writing device settings it never chose
    /// to carry.
    static func isBackedUp(_ key: String) -> Bool {
        preferenceKeySet.contains(key) || preferenceKeyPrefixes.contains { key.hasPrefix($0) }
    }

    // MARK: - Merge Policy

    /// How a restored value combines with whatever the device already holds.
    enum MergePolicy: Equatable {
        /// The backup's value replaces the local one (the default; matches
        /// how records are restored — the backup wins for anything it holds).
        case replace
        /// Lists of device-specific tokens: keep the local entries and append
        /// restored ones that aren't already present.
        case unionArray
        /// Maps keyed by something on this device (album filenames): restored
        /// entries fill gaps, local entries win on conflict.
        case mergeDictionaryLocalWins
    }

    static func mergePolicy(for key: String) -> MergePolicy {
        switch key {
        case UserDefaultsKeys.albumsFolderBookmarks:
            return .unionArray
        case UserDefaultsKeys.albumsFingerprints, UserDefaultsKeys.albumsLastSeenModDates:
            return .mergeDictionaryLocalWins
        default:
            return .replace
        }
    }

    // MARK: - Export

    /// Builds a PreferencesDTO from current user preferences.
    @MainActor static func buildPreferencesDTO() -> PreferencesDTO {
        let syncedStore = SyncedPreferencesStore.shared
        let defaults = UserDefaults.standard
        var map: [String: PreferenceValueDTO] = [:]

        var keys = Set(preferenceKeys)
        for prefix in preferenceKeyPrefixes {
            keys.formUnion(syncedStore.storedKeys(withPrefix: prefix))
            keys.formUnion(defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) })
        }

        for key in keys {
            let obj: Any? = syncedStore.isSynced(key: key) ? syncedStore.get(key: key) : defaults.object(forKey: key)
            if let obj, let value = dtoValue(for: obj) {
                map[key] = value
            }
        }

        return PreferencesDTO(values: map)
    }

    /// Converts a stored preference object into its backup representation.
    /// Returns nil for values that can't be represented (nothing in the key
    /// list produces one; this keeps a stray object from being stringified).
    static func dtoValue(for obj: Any) -> PreferenceValueDTO? {
        switch obj {
        case let number as NSNumber:
            // Bools, Ints, and Doubles all surface as NSNumber from UserDefaults;
            // `as? Bool` alone would misfile any 0/1 integer as a Bool.
            switch String(cString: number.objCType) {
            case "c", "B": return .bool(number.boolValue)
            case "d", "f": return .double(number.doubleValue)
            default: return .int(number.intValue)
            }
        case let s as String:
            return .string(s)
        case let data as Data:
            return .data(data)
        case let date as Date:
            return .date(date)
        case is [Any], is [String: Any]:
            guard PropertyListSerialization.propertyList(obj, isValidFor: .binary),
                  let data = try? PropertyListSerialization.data(fromPropertyList: obj, format: .binary, options: 0)
            else { return nil }
            return .plist(data)
        default:
            return nil
        }
    }

    // MARK: - Import

    /// Applies a PreferencesDTO to user preferences: only the keys backups
    /// carry (`isBackedUp`). The school-year settings an older backup kept
    /// under another key are read by `applySchoolYearSettings`.
    @MainActor static func applyPreferencesDTO(_ dto: PreferencesDTO) {
        let syncedStore = SyncedPreferencesStore.shared
        let defaults = UserDefaults.standard

        for (key, value) in dto.values where isBackedUp(key) {
            guard let restored = nativeValue(for: value) else { continue }
            let synced = syncedStore.isSynced(key: key)
            let local: Any? = synced ? syncedStore.get(key: key) : defaults.object(forKey: key)
            let merged = merge(restored: restored, local: local, policy: mergePolicy(for: key))

            if synced {
                syncedStore.set(merged, forKey: key)
            } else {
                defaults.set(merged, forKey: key)
            }
        }
        applySchoolYearSettings(from: dto, defaults: defaults)
    }

    /// A backup from before the counter mode had its own key carries the stored epoch date
    /// instead: present meant counters reset at the year start. Then the restored school-year
    /// settings are published to the class's other devices, since restoring is an explicit
    /// choice (`SchoolYearSync`).
    @MainActor static func applySchoolYearSettings(from dto: PreferencesDTO, defaults: UserDefaults) {
        let modeKey = UserDefaultsKeys.schoolYearCountersResetAtYearStart
        if dto.values[modeKey] == nil, dto.values[UserDefaultsKeys.schoolYearCounterEpoch] != nil {
            defaults.set(true, forKey: modeKey)
        }
        let schoolYearKeys = [
            UserDefaultsKeys.schoolYearStartMonth, UserDefaultsKeys.schoolYearStartDay, modeKey,
            UserDefaultsKeys.schoolYearCounterEpoch
        ]
        guard schoolYearKeys.contains(where: { dto.values[$0] != nil }) else { return }
        SchoolYearSync.shared?.localSettingsReplaced()
    }

    /// Converts a backup representation back into the object UserDefaults stores.
    static func nativeValue(for value: PreferenceValueDTO) -> Any? {
        switch value {
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        case .data(let data): return data
        case .date(let date): return date
        case .plist(let data):
            return try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        }
    }

    /// Combines a restored value with the device's current value under `policy`.
    static func merge(restored: Any, local: Any?, policy: MergePolicy) -> Any {
        switch policy {
        case .replace:
            return restored
        case .unionArray:
            guard let restoredList = restored as? [AnyHashable] else { return restored }
            let localList = (local as? [AnyHashable]) ?? []
            let present = Set(localList)
            return localList + restoredList.filter { !present.contains($0) }
        case .mergeDictionaryLocalWins:
            guard let restoredMap = restored as? [String: Any] else { return restored }
            var merged = restoredMap
            for (key, value) in (local as? [String: Any]) ?? [:] {
                merged[key] = value
            }
            return merged
        }
    }
}
