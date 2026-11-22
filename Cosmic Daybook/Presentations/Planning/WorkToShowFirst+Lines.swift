// WorkToShowFirst+Lines.swift
// The practice warnings' words on screen (plan "Cut unused features and close
// the lesson loop", Phase 4): "Practicing The Distributive Law" beside a child
// in a picker, "Still practicing: Ora L (The Distributive Law)" on Today's
// lesson rows. Chat words its own (`MCPNotebookTools+PracticeWarnings`).

import Foundation

extension WorkToShowFirst {

    /// What one child is still practicing, for her picker row:
    /// "Practicing The Distributive Law", "Practicing The Distributive Law and
    /// 1 more". Nil with nothing open. One lesson is named once, however many
    /// pieces of work she has on it.
    static func practicingLine(_ items: [Item]) -> String? {
        let lessons = lessonNames(items)
        guard let first = lessons.first else { return nil }
        return lessons.count == 1 ? "Practicing \(first)" : "Practicing \(first) and \(lessons.count - 1) more"
    }

    /// Who on a lesson is still practicing an earlier one, for Today's row:
    /// "Still practicing: Ora L (The Distributive Law), Maya S (Bead Frame and
    /// 1 more)". Children A–Z by the name given; nil when nobody is.
    static func stillPracticingLine(_ byChild: ByChild, name: (UUID) -> String) -> String? {
        let entries: [(name: String, lessons: [String])] = byChild.compactMap { child, items in
            let lessons = lessonNames(items)
            return lessons.isEmpty ? nil : (name(child), lessons)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !entries.isEmpty else { return nil }
        let parts = entries.map { entry in
            let first = entry.lessons[0]
            let what = entry.lessons.count == 1 ? first : "\(first) and \(entry.lessons.count - 1) more"
            return "\(entry.name) (\(what))"
        }
        return "Still practicing: " + parts.joined(separator: ", ")
    }

    /// The earlier lessons in `items`, in their order, each once.
    private static func lessonNames(_ items: [Item]) -> [String] {
        var seen = Set<String>()
        return items.compactMap { item in seen.insert(item.lessonID).inserted ? item.lessonName : nil }
    }
}
