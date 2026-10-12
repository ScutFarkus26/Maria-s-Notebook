//
//  NotebookToolText.swift
//  Cosmic Daybook
//
//  Keeps what a notebook tool hands the on-device model small enough to fit.
//

import Foundation

/// The on-device model's whole context is a few thousand tokens, instructions
/// and the classroom snapshot included, and Recent Notes used to return up to
/// 20 notes in full, so a child with long notes overflowed it and the answer
/// failed (bug hunt 2026-10-11 #53).
nonisolated enum NotebookToolText {
    /// The most of one note's text a reply carries.
    static let noteCharacterLimit = 300
    /// The most a reply's list of notes carries in all.
    static let replyCharacterLimit = 2_400

    /// `text` on one line, cut to `limit` characters at a word boundary and
    /// marked with "…" when cut.
    static func excerpt(_ text: String, limit: Int = noteCharacterLimit) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard flat.count > limit else { return flat }
        let cut = flat.prefix(limit)
        let atWord = cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return atWord.trimmingCharacters(in: .whitespaces) + "…"
    }

    /// The leading `lines` that fit in `limit` characters (a newline after
    /// each), always at least the first.
    static func fitting(_ lines: [String], limit: Int = replyCharacterLimit) -> [String] {
        var kept: [String] = []
        var used = 0
        for line in lines {
            let cost = line.count + 1
            guard kept.isEmpty || used + cost <= limit else { break }
            kept.append(line)
            used += cost
        }
        return kept
    }
}
