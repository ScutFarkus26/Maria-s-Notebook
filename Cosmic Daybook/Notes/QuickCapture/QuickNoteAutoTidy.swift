// QuickNoteAutoTidy.swift
// Applying the name tagger's tidy-ups to a Quick Note's text without moving
// her cursor. Split out of QuickNoteViewModel.analyzeText (2026-10-10).

import Foundation
import OSLog
import SwiftUI

/// Quick Note's auto-tidy: the tagger's replacements applied to the text,
/// from the end of the text back.
///
/// Each replacement goes only where the tagger found it (`TextReplacement.range`),
/// and only while the text there still reads exactly as it did: applying "S A"
/// everywhere, ignoring case, once turned "She's a fast reader" into
/// "She'Sam A fast reader". A replacement with no range (one made by hand) goes
/// on every whole-word, same-case occurrence.
///
/// The text used to be swapped in wholesale, which put the cursor at the end
/// of the note: tidying "maya" while she was writing in the middle of a note
/// threw her to the bottom. The cursor (a UTF-16 offset, as `NSRange` counts)
/// now moves with the text around it: by the change in length when a tidied
/// word comes before it, to the end of the word when it was inside one.
enum QuickNoteAutoTidy {
    private static let logger = Logger.notes

    /// The tidied text and where the cursor goes, or nil when nothing changed.
    static func apply(
        _ replacements: [TextReplacement], to text: String, cursor: Int?
    ) -> (text: String, cursor: Int?)? {
        // Every place to change, as (where, replacement), checked against the
        // text as it is now; later places first so earlier ranges stay put.
        var edits: [(range: NSRange, replacement: String)] = []
        for replacement in replacements where replacement.originalText != replacement.replacement {
            if let range = replacement.range {
                guard let found = Range(range, in: text), text[found] == replacement.originalText else { continue }
                edits.append((range, replacement.replacement))
            } else {
                edits += wholeWordRanges(of: replacement.originalText, in: text).map { ($0, replacement.replacement) }
            }
        }
        edits.sort { $0.range.location > $1.range.location }

        var updatedText = text
        var cursor = cursor
        var hasChanges = false
        var lowestChanged = Int.max
        for edit in edits where NSMaxRange(edit.range) <= lowestChanged {
            guard let range = Range(edit.range, in: updatedText) else { continue }
            updatedText.replaceSubrange(range, with: edit.replacement)
            cursor = cursor.map { moved($0, past: edit.range, becoming: edit.replacement.utf16.count) }
            lowestChanged = edit.range.location
            hasChanges = true
        }
        return hasChanges ? (updatedText, cursor) : nil
    }

    /// Every whole-word occurrence of `word` in `text`, same case only.
    private static func wholeWordRanges(of word: String, in text: String) -> [NSRange] {
        let pattern = "\\b\(NSRegularExpression.escapedPattern(for: word))\\b"
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            return regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).map(\.range)
        } catch {
            logger.warning("Invalid regex pattern '\(pattern)': \(error)")
            return []
        }
    }

    /// Where a cursor at `offset` lands once `range` is replaced by text
    /// `length` UTF-16 units long.
    static func moved(_ offset: Int, past range: NSRange, becoming length: Int) -> Int {
        if offset >= range.location + range.length { return offset + length - range.length }
        if offset > range.location { return range.location + length }
        return offset
    }

    /// The cursor's UTF-16 offset in `text`: the end of the selection, or nil
    /// when there is none or it doesn't fit the text.
    static func cursorOffset(of selection: TextSelection?, in text: String) -> Int? {
        guard case .selection(let range) = selection?.indices, range.upperBound <= text.endIndex else { return nil }
        return range.upperBound.utf16Offset(in: text)
    }

    /// An insertion point at the UTF-16 `offset` in `text`, kept inside it.
    static func selection(at offset: Int, in text: String) -> TextSelection {
        let clamped = min(max(offset, 0), text.utf16.count)
        return TextSelection(insertionPoint: String.Index(utf16Offset: clamped, in: text))
    }
}
