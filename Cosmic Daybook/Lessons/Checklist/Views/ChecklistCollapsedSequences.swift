//
//  ChecklistCollapsedSequences.swift
//  Cosmic Daybook
//
//  Which sequence bands the guide folded away, remembered per curriculum area under
//  one key (`UserDefaultsKeys.checklistCollapsedSequences`): a dictionary from the
//  area's folded name to the folded names of its collapsed sequences. The unfiled
//  "Other" band is the empty string.
//

import Foundation

enum ChecklistCollapsedSequences {

    /// The collapsed sequences for `area`, in folded form (see `key(for:)`).
    static func load(area: String, defaults: UserDefaults = .standard) -> Set<String> {
        let stored = defaults.dictionary(forKey: UserDefaultsKeys.checklistCollapsedSequences) ?? [:]
        let names = stored[key(for: area)] as? [String] ?? []
        return Set(names)
    }

    /// Saves `collapsed` for `area`; an empty set removes the area's entry.
    static func save(_ collapsed: Set<String>, area: String, defaults: UserDefaults = .standard) {
        let areaKey = key(for: area)
        guard !areaKey.isEmpty else { return }
        var stored = defaults.dictionary(forKey: UserDefaultsKeys.checklistCollapsedSequences) ?? [:]
        if collapsed.isEmpty {
            stored.removeValue(forKey: areaKey)
        } else {
            stored[areaKey] = collapsed.sorted()
        }
        if stored.isEmpty {
            defaults.removeObject(forKey: UserDefaultsKeys.checklistCollapsedSequences)
        } else {
            defaults.set(stored, forKey: UserDefaultsKeys.checklistCollapsedSequences)
        }
    }

    /// The form areas and sequences are stored and compared in: trimmed, case- and
    /// diacritic-folded, so "Math " and "math" share an entry as they share a grid.
    static func key(for name: String) -> String {
        name.trimmed().folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
