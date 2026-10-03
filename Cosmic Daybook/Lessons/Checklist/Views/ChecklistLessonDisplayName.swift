//
//  ChecklistLessonDisplayName.swift
//  Cosmic Daybook
//
//  The name a checklist row shows. Under a section caption the section's name is
//  already on screen, so "Stamp Game: Static Addition" under Stamp Game reads
//  "Static Addition". Display only: search, VoiceOver and the hover text keep the
//  lesson's real name.
//

import Foundation

enum ChecklistLessonDisplayName {

    /// Characters that may sit between the section's name and the rest of the lesson's.
    private static let separators = CharacterSet(charactersIn: ":-–—·,").union(.whitespaces)

    /// `name` without a leading `section` and the separator after it. The whole name
    /// when there's no section, the name doesn't start with it on a word boundary, or
    /// nothing would be left.
    static func displayName(lessonName name: String, section: String) -> String {
        let trimmedName = name.trimmed()
        let trimmedSection = section.trimmed()
        guard !trimmedSection.isEmpty,
              let range = trimmedName.range(
                of: trimmedSection, options: [.anchored, .caseInsensitive, .diacriticInsensitive]
              )
        else { return trimmedName }

        let rest = trimmedName[range.upperBound...]
        // "Stamp Games" must not lose "Stamp Game": the match has to end a word.
        guard let first = rest.unicodeScalars.first, separators.contains(first) else { return trimmedName }

        let stripped = String(rest.unicodeScalars.drop { separators.contains($0) })
        guard !stripped.isEmpty else { return trimmedName }
        return stripped
    }
}
