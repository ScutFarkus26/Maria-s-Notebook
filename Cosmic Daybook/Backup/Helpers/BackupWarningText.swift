// BackupWarningText.swift
// The restore's warnings in plain words, translated where they are shown.
//
// The warnings themselves stay as the restore writes them: the frozen copy of
// the old restore (`Cosmic Daybook Tests/Backup/BackupService+LegacyRestore.swift`)
// and the old preview analyzer write the same text, and the equivalence tests
// compare the two word for word. So the restore preview and the summary show
// `plain(_:)` of each one, and keep the raw lines under Details.

import Foundation

nonisolated enum BackupWarningText {

    /// What the guide reads for a warning the restore or its preview wrote.
    static func plain(_ raw: String) -> String {
        if raw.hasPrefix("iCloud sync reported a failure") {
            return "Your restored notebook is saved on this device but hasn't reached iCloud yet. It'll keep trying."
        }
        if raw.hasPrefix("iCloud sync is still running") {
            return "Your restored notebook is still going up to iCloud. "
                + "Keep the app open for a moment so it can finish."
        }
        if raw.hasPrefix("Unknown entity '") {
            return "Part of this backup was made by a newer version of the app and was skipped. "
                + "Update Cosmic Daybook to restore all of it."
        }
        if let range = raw.range(of: " records could not be read from this backup") {
            let noun = BackupPlainNames.noun(for: String(raw[..<range.lowerBound])).lowercased()
            return "Part of this backup was damaged and was skipped (\(noun))."
        }
        if let count = leadingCount(raw, before: " lesson assignments reference lessons missing") {
            return count == 1
                ? "1 planned lesson points to a lesson that isn't in this backup or your notebook. "
                    + "It'll reconnect once that lesson is added."
                : "\(count.formatted()) planned lessons point to lessons that aren't in this backup or your notebook. "
                    + "They'll reconnect once those lessons are added."
        }
        if let count = leadingCount(raw, before: " note photo(s) could not be restored") {
            return count == 1
                ? "1 note photo couldn't be restored."
                : "\(count.formatted()) note photos couldn't be restored."
        }
        if raw.hasPrefix("This backup includes bookmarks, notes, highlights, or drawings") {
            return raw // already plain (`albumReattachWarning`)
        }
        if raw.contains(remindersNotHere) {
            return raw // already plain (`notesMissingTheirReminder`)
        }
        return fallback
    }

    private static let remindersNotHere = "this device doesn't have"

    /// Notes the backup links to a reminder this device doesn't have: reminders
    /// aren't restored (they come from Apple's Reminders), so the link stays off.
    static func notesMissingTheirReminder(_ count: Int) -> String {
        count == 1
            ? "1 note was linked to a reminder \(remindersNotHere), so that link is off for now. "
                + "The note itself is back."
            : "\(count.formatted()) notes were linked to reminders \(remindersNotHere), so those links are "
                + "off for now. The notes themselves are all back."
    }

    /// What a warning this file doesn't know reads as.
    static let fallback = "Part of this backup didn't come through as it was. The details are below."

    /// The plain sentences for `warnings`, each once, in order.
    static func plain(_ warnings: [String]) -> [String] {
        var seen = Set<String>()
        return warnings.map(plain).filter { seen.insert($0).inserted }
    }

    /// The raw warnings that read differently on screen, for the Details disclosure
    /// (empty, so no disclosure, when every one is already plain).
    static func details(_ warnings: [String]) -> String {
        warnings.filter { plain($0) != $0 }.joined(separator: "\n")
    }

    /// The number a warning starts with, when `marker` follows it.
    private static func leadingCount(_ raw: String, before marker: String) -> Int? {
        guard let range = raw.range(of: marker) else { return nil }
        return Int(raw[..<range.lowerBound])
    }
}
