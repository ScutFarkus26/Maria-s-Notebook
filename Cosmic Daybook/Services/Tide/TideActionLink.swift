// TideActionLink.swift
// The address Tide gives each of its to-dos, and the line a to-do the
// notebook sent carries in its Tide note (plan "Simplify the app", Phase 10).

import Foundation

/// A Tide to-do's address, `tide://box/<workspace path>?text=<words>`: the
/// list it is a line of and its words. Stored on the notebook's copy as
/// `CDTodoItem.tideLink`.
///
/// Built exactly as Tide builds it (`TideCore/Link.swift`, read 2026-10-18):
/// every byte of a path segment and of the words that isn't unreserved
/// (`A–Z a–z 0–9 - . _ ~`) is percent-encoded, so the string the notebook
/// makes for a row `list_actions` returns is the string Tide puts in a
/// write's reply. Tide makes it from the action's words, so rewording the
/// action in Tide gives it a new address; the sync finds the action again by
/// the `notebook:` line in its note (`TideNotebookMarker`).
nonisolated struct TideActionLink: Hashable, Sendable {
    /// The list's workspace path, "Areas/My Classrooms/Upper Elementary/To do.md".
    let file: String
    /// The action's words as Tide holds them.
    let text: String

    private static let prefix = "tide://box/"
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    init(file: String, text: String) {
        self.file = file
        self.text = text
    }

    /// Reads a stored address back; nil for anything that isn't a Tide box link.
    init?(_ string: String) {
        guard string.hasPrefix(Self.prefix) else { return nil }
        let rest = string.dropFirst(Self.prefix.count)
        guard let query = rest.range(of: "?text=") else { return nil }
        let segments = rest[..<query.lowerBound].split(separator: "/").map {
            $0.removingPercentEncoding ?? String($0)
        }
        guard !segments.isEmpty,
              let words = String(rest[query.upperBound...]).removingPercentEncoding else { return nil }
        file = segments.joined(separator: "/")
        text = words
    }

    /// The address as Tide spells it.
    var string: String {
        let path = file.split(separator: "/").map(Self.encode).joined(separator: "/")
        return Self.prefix + path + "?text=" + Self.encode(text)
    }

    /// The list's name for the notebook's screens: the folder a `To do.md` or
    /// `Plan.md` sits in ("Upper Elementary", "My Classrooms"), or the file's
    /// own name without ".md".
    var listName: String { Self.listName(ofFile: file) }

    static func listName(ofFile file: String) -> String {
        let parts = file.split(separator: "/").map(String.init)
        guard let last = parts.last else { return file }
        let generic = ["to do.md", "todo.md", "plan.md"]
        if generic.contains(last.lowercased()), parts.count >= 2 {
            return parts[parts.count - 2]
        }
        return last.hasSuffix(".md") ? String(last.dropLast(3)) : last
    }

    private static func encode<S: StringProtocol>(_ part: S) -> String {
        String(part).addingPercentEncoding(withAllowedCharacters: unreserved) ?? String(part)
    }
}

/// The line a to-do sent from the notebook carries in its Tide note,
/// `notebook:<uuid>`, naming the notebook to-do it came from. It is how the
/// sync knows its own actions again after Tide's address for one changed
/// (rewording in Tide) or when the notebook stopped between sending a to-do
/// and saving its address (a crash mid-push).
nonisolated enum TideNotebookMarker {
    private static let word = "notebook:"

    /// The line for `id`.
    static func line(for id: UUID) -> String {
        word + id.uuidString
    }

    /// The notebook to-do a Tide note names, if it names one.
    static func todoID(in note: String?) -> UUID? {
        guard let note else { return nil }
        var searchRange = note.startIndex..<note.endIndex
        while let found = note.range(of: word, options: .caseInsensitive, range: searchRange) {
            let candidate = note[found.upperBound...].prefix(36)
            if candidate.count == 36, let id = UUID(uuidString: String(candidate)) {
                return id
            }
            searchRange = found.upperBound..<note.endIndex
        }
        return nil
    }

    /// The note without its `notebook:` lines, for the notebook's own copy of
    /// a note.
    static func removing(from note: String?) -> String {
        guard let note else { return "" }
        let kept = note.components(separatedBy: "\n").filter { line in
            !line.trimmingCharacters(in: .whitespaces).lowercased().hasPrefix(word)
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
