// ParshaMetadataService.swift
// Loads bundled parsha metadata (passage range + topics) from parsha_metadata.json.

import Foundation
import os.log

struct ParshaMetadata: Decodable, Sendable {
    let key: String
    let passageRange: String
    let passageRangeHebrew: String
    let topics: [String]

    /// The transliterated Hebrew book name + chapter:verse range
    /// (e.g., "Bereishit 1:1–6:8" instead of "Genesis 1:1–6:8").
    var torahReference: String {
        let bookNames: [(english: String, transliterated: String)] = [
            ("Genesis", "Bereishit"),
            ("Exodus", "Shemot"),
            ("Leviticus", "Vayikra"),
            ("Numbers", "Bamidbar"),
            ("Deuteronomy", "Devarim")
        ]
        for (english, transliterated) in bookNames where passageRange.hasPrefix(english) {
            return transliterated + passageRange.dropFirst(english.count)
        }
        return passageRange
    }
}

enum ParshaMetadataService {

    private static let logger = Logger.app(category: "ParshaMetadataService")

    /// Keys that represent combined parshiot. Excluded from the topic index so single
    /// parshas are the source of truth for which-parsha-mentions-which-topic.
    private static let combinedKeys: Set<String> = [
        "vayakhel-pekudei",
        "tazria-metzora",
        "acharei-mot-kedoshim",
        "behar-bechukotai",
        "chukat-balak",
        "matot-masei",
        "nitzavim-vayelech"
    ]

    private struct Library: Decodable {
        let version: Int
        let parshas: [ParshaMetadata]
    }

    private static let metadataByKey: [String: ParshaMetadata] = {
        guard let url = Bundle.main.url(forResource: "parsha_metadata", withExtension: "json") else {
            logger.warning("parsha_metadata.json not found in bundle")
            return [:]
        }
        do {
            let data = try Data(contentsOf: url)
            let library = try JSONDecoder().decode(Library.self, from: data)
            return Dictionary(uniqueKeysWithValues: library.parshas.map { ($0.key, $0) })
        } catch {
            logger.error("Failed to decode parsha_metadata.json: \(error.localizedDescription)")
            return [:]
        }
    }()

    static func metadata(forKey key: String) -> ParshaMetadata? {
        metadataByKey[key]
    }

}
