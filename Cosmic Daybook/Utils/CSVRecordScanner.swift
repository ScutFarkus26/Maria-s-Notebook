import Foundation

/// Reads CSV records from UTF-8 bytes instead of `Character`s.
///
/// `CSVParser.characterRecords` walks `Array(content)`: 16 bytes of memory
/// per character before a single field is read, and a grapheme-cluster break
/// computed for every one. The only characters the reader acts on are `"`,
/// `,` and a newline, all single ASCII bytes, and ASCII bytes never occur
/// inside a longer UTF-8 sequence, so the same state machine can run over
/// the text's own bytes and copy whole runs of everything else.
///
/// The two readings differ only where a delimiter is not a character by
/// itself: a combining mark, zero-width joiner or spacing mark after `"` or
/// `,`, or a prepended mark before it, makes one grapheme cluster that the
/// character reader takes as text. Whenever a delimiter touches a non-ASCII
/// neighbour, the scanner asks the string whether that byte is a whole
/// character, and gives up (nil) if it is not, so the caller reads the text
/// by characters as before. A newline is always a character by itself, and
/// the text reaching here holds no carriage return.
enum CSVRecordScanner {
    private static let quote: UInt8 = 0x22
    private static let comma: UInt8 = 0x2C
    private static let newline: UInt8 = 0x0A
    private static let carriageReturn: UInt8 = 0x0D

    /// The records of normalized `content`, exactly as
    /// `CSVParser.characterRecords` reads them, or nil when a byte reading
    /// could differ from the character reading.
    static func records(in content: String) -> [[String]]? {
        var content = content
        content.makeContiguousUTF8()
        let text = content
        return text.utf8.withContiguousStorageIfAvailable { bytes in
            // A carriage return left after normalizing (inside a cluster the
            // replacements kept whole) would join the newline after it.
            guard !bytes.contains(carriageReturn) else { return nil }
            return scan(bytes, in: text)
        } ?? nil
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func scan(_ bytes: UnsafeBufferPointer<UInt8>, in text: String) -> [[String]]? {
        var rows: [[String]] = []
        var currentRow: [String] = []
        var field: [UInt8] = []
        var insideQuotes = false
        // True once any field content (a byte, comma, or opening quote) has
        // been seen since the last record-terminating newline — see
        // `CSVParser.characterRecords`.
        var pendingRecord = false
        var index = 0

        /// Whether the delimiter at `position` is a character by itself.
        func standsAlone(_ position: Int) -> Bool {
            let asciiBefore = position == 0 || bytes[position - 1] < 0x80
            let asciiAfter = position + 1 == bytes.count || bytes[position + 1] < 0x80
            return (asciiBefore && asciiAfter) || isWholeCharacter(atUTF8Offset: position, in: text)
        }

        func appendField() {
            // A field is the bytes between ASCII delimiters of valid UTF-8, so
            // it is valid UTF-8 too and this decoding replaces nothing.
            // swiftlint:disable:next optional_data_string_conversion
            currentRow.append(String(decoding: field, as: UTF8.self))
            field.removeAll(keepingCapacity: true)
        }

        while index < bytes.count {
            let byte = bytes[index]
            if byte == quote || byte == comma, !standsAlone(index) { return nil }
            if insideQuotes {
                pendingRecord = true
                if byte == quote {
                    // A doubled quote is an escaped quote.
                    if index + 1 < bytes.count && bytes[index + 1] == quote {
                        guard standsAlone(index + 1) else { return nil }
                        field.append(quote)
                        index += 1
                    } else {
                        insideQuotes = false
                    }
                } else {
                    field.append(byte)
                }
            } else {
                switch byte {
                case quote:
                    pendingRecord = true
                    insideQuotes = true
                case comma:
                    pendingRecord = true
                    appendField()
                case newline:
                    appendField()
                    rows.append(currentRow)
                    currentRow = []
                    pendingRecord = false
                default:
                    pendingRecord = true
                    field.append(byte)
                }
            }
            index += 1
        }
        if pendingRecord {
            appendField()
            rows.append(currentRow)
        }
        return rows
    }

    /// Whether the one-byte character at `offset` is a whole grapheme cluster
    /// of `text` — what `Array(text)` would have made a `Character` by itself.
    private static func isWholeCharacter(atUTF8Offset offset: Int, in text: String) -> Bool {
        let utf8 = text.utf8
        let start = utf8.index(utf8.startIndex, offsetBy: offset)
        let end = utf8.index(after: start)
        guard String.Index(start, within: text) != nil else { return false }
        return end == utf8.endIndex || String.Index(end, within: text) != nil
    }
}
