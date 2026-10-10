// HebrewParshaService+CombinedKeys.swift
// The seven doubled parshiot, and how a lesson's tag meets a week's key.
//
// A doubled pair is read as one combined week in some years ("vayakhel-pekudei")
// and as two weeks in others. A lesson is tagged once, with whichever key the
// guide picked, so a week shows every lesson tagged with its own key or with
// any key that shares a parsha with it: a combined week shows lessons tagged on
// either half, and a single week shows lessons tagged on the combined week that
// contains it.

import CoreData
import Foundation

extension HebrewParshaService {

    /// One doubled pair and the key used when its halves are read together.
    struct DoubledPair: Sendable {
        let first: String
        let second: String
        var combined: String { "\(first)-\(second)" }
    }

    /// The doubled pairs, in annual-cycle order.
    static let doubledPairs: [DoubledPair] = [
        DoubledPair(first: "vayakhel", second: "pekudei"),
        DoubledPair(first: "tazria", second: "metzora"),
        DoubledPair(first: "acharei-mot", second: "kedoshim"),
        DoubledPair(first: "behar", second: "bechukotai"),
        DoubledPair(first: "chukat", second: "balak"),
        DoubledPair(first: "matot", second: "masei"),
        DoubledPair(first: "nitzavim", second: "vayelech")
    ]

    /// Every key a lesson can be tagged with, in annual-cycle order: the 54
    /// parshiot with each combined week listed after its second half.
    static let pickerKeys: [String] = allParshaKeys.flatMap { key -> [String] in
        if let pair = doubledPairs.first(where: { $0.second == key }) {
            return [key, pair.combined]
        }
        return [key]
    }

    /// The tags whose lessons belong to the week `key` is read: the key itself,
    /// both halves of a combined week, and the combined week a single half
    /// belongs to.
    static func matchingKeys(for key: String) -> [String] {
        if let pair = doubledPairs.first(where: { $0.combined == key }) {
            return [key, pair.first, pair.second]
        }
        if let pair = doubledPairs.first(where: { $0.first == key || $0.second == key }) {
            return [key, pair.combined]
        }
        return [key]
    }

    /// Whether a lesson tagged `tag` belongs to the week `key` is read.
    static func tag(_ tag: String?, matches key: String) -> Bool {
        guard let tag, !tag.isEmpty else { return false }
        return matchingKeys(for: key).contains(tag)
    }

    /// Lessons tagged to the week `key` is read, by `matchingKeys(for:)`.
    static func lessonsPredicate(forParshaKey key: String) -> NSPredicate {
        NSPredicate(format: "parshaKey IN %@", matchingKeys(for: key))
    }

    /// How many lessons belong to the week `key` is read, given the number of
    /// lessons carrying each tag.
    static func lessonCount(forParshaKey key: String, countsByTag: [String: Int]) -> Int {
        matchingKeys(for: key).reduce(0) { $0 + (countsByTag[$1] ?? 0) }
    }
}
