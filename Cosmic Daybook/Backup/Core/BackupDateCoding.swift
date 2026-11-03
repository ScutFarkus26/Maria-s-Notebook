// BackupDateCoding.swift
// How every date in a backup archive is written and read.

import Foundation

/// The one date format of the backup archive: ISO 8601 in UTC, with
/// milliseconds when the date has any (`2026-11-02T08:00:00.123Z`), and
/// whole seconds when it has none (`2026-11-02T08:00:00Z`).
///
/// Until 2026-11 the archive used `JSONEncoder`'s `.iso8601`, which writes
/// whole seconds only: rows made within one second could swap order after a
/// restore, and a "newer wins" check compared a backup's truncated date with
/// the stored full one (bug hunt 2026-11-02 #20). Apple's
/// `Date.ISO8601FormatStyle(includingFractionalSeconds: true)` keeps the
/// fraction to the millisecond.
///
/// Reading accepts both forms, so every older archive (whole seconds) still
/// restores. A whole-second date is written as before, so an archive of such
/// dates is byte for byte what older builds wrote.
nonisolated enum BackupDateCoding {

    /// For every encoder that writes into an archive.
    static let encodingStrategy: JSONEncoder.DateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(string(from: date))
    }

    /// For every decoder that reads from an archive.
    static let decodingStrategy: JSONDecoder.DateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        guard let date = date(from: text) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Expected an ISO 8601 date, found \(text)"
            )
        }
        return date
    }

    private static let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let wholeSeconds = Date.ISO8601FormatStyle()

    /// `date` as the archive writes it.
    static func string(from date: Date) -> String {
        let text = date.formatted(withFraction)
        // No fraction to keep: the form older builds wrote.
        guard text.hasSuffix(".000Z") else { return text }
        return String(text.dropLast(".000Z".count)) + "Z"
    }

    /// The date an archive wrote as `text`, with or without a fraction; nil
    /// when it isn't an ISO 8601 date.
    static func date(from text: String) -> Date? {
        if let date = try? Date(text, strategy: withFraction) { return date }
        return try? Date(text, strategy: wholeSeconds)
    }
}
