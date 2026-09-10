// CurriculumMapSettings.swift
// The guide's choices for the Three-Year View: how long an area can go
// without a presentation before it is flagged, per area, because Art and
// Parsha have different rhythms than Math. Stored in UserDefaults and carried
// by backups (BackupPreferencesService).

import Foundation

@Observable
final class CurriculumMapSettings {
    static let defaultUntouchedDays = 90
    static let untouchedChoices = [30, 45, 60, 90, 120, 180, 270, 365]

    private let defaults: UserDefaults

    /// Days without a presentation before an area is flagged, unless overridden.
    var defaultUntouchedDays: Int {
        didSet { defaults.set(defaultUntouchedDays, forKey: UserDefaultsKeys.curriculumMapUntouchedDays) }
    }

    /// Per-area overrides, keyed by the area's filing key.
    private(set) var untouchedDaysByArea: [String: Int] {
        didSet { defaults.set(untouchedDaysByArea, forKey: UserDefaultsKeys.curriculumMapUntouchedDaysByArea) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.integer(forKey: UserDefaultsKeys.curriculumMapUntouchedDays)
        defaultUntouchedDays = stored > 0 ? stored : Self.defaultUntouchedDays
        untouchedDaysByArea = defaults.dictionary(forKey: UserDefaultsKeys.curriculumMapUntouchedDaysByArea)
            as? [String: Int] ?? [:]
    }

    func untouchedDays(for area: String) -> Int {
        untouchedDaysByArea[CurriculumMapEngine.filingKey(area)] ?? defaultUntouchedDays
    }

    func hasOverride(for area: String) -> Bool {
        untouchedDaysByArea[CurriculumMapEngine.filingKey(area)] != nil
    }

    /// Pass nil to fall back to the default again.
    func setUntouchedDays(_ days: Int?, for area: String) {
        let key = CurriculumMapEngine.filingKey(area)
        if let days, days > 0 {
            untouchedDaysByArea[key] = days
        } else {
            untouchedDaysByArea.removeValue(forKey: key)
        }
    }
}
