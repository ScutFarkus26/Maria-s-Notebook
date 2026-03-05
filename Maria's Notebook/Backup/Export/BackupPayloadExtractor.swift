import Foundation

// MARK: - Backup Payload Extractor

/// Helpers for extracting payload data from backup files.
enum BackupPayloadExtractor {

    // MARK: - Extract Payload Bytes

    /// Extracts the raw payload bytes from a backup envelope's JSON data.
    /// This allows for checksum verification before decoding the full payload.
    static func extractPayloadBytes(from envelopeData: Data) throws -> Data? {
        guard let jsonString = String(data: envelopeData, encoding: .utf8) else { return nil }

        let payloadKeyPattern = "\"payload\""
        var searchRange = jsonString.startIndex..<jsonString.endIndex

        while let keyRange = jsonString.range(of: payloadKeyPattern, range: searchRange) {
            var checkIndex = keyRange.lowerBound

            if checkIndex > jsonString.startIndex {
                checkIndex = jsonString.index(before: checkIndex)

                while checkIndex > jsonString.startIndex && jsonString[checkIndex].isWhitespace {
                    checkIndex = jsonString.index(before: checkIndex)
                }

                let ch = jsonString[checkIndex]
                if checkIndex >= jsonString.startIndex && (ch == "{" || ch == ",") {
                    return extractPayloadValue(from: jsonString, startingAt: keyRange.upperBound)
                }
            } else if checkIndex == jsonString.startIndex {
                return extractPayloadValue(from: jsonString, startingAt: keyRange.upperBound)
            }

            searchRange = keyRange.upperBound..<jsonString.endIndex
        }

        return nil
    }

    // MARK: - Private Helpers

    /// Extracts the payload value (JSON object) starting from the given index.
    private static func extractPayloadValue(from jsonString: String, startingAt: String.Index) -> Data? {
        var searchStart = startingAt

        // Skip whitespace
        while searchStart < jsonString.endIndex && jsonString[searchStart].isWhitespace {
            searchStart = jsonString.index(after: searchStart)
        }

        // Expect colon
        guard searchStart < jsonString.endIndex && jsonString[searchStart] == ":" else { return nil }
        searchStart = jsonString.index(after: searchStart)

        // Skip whitespace
        while searchStart < jsonString.endIndex && jsonString[searchStart].isWhitespace {
            searchStart = jsonString.index(after: searchStart)
        }

        // Expect opening brace
        guard searchStart < jsonString.endIndex && jsonString[searchStart] == "{" else { return nil }

        // Track braces to find matching close
        var braceCount = 0
        var inString = false
        var escapeNext = false
        let valueStart = searchStart
        var valueEnd = searchStart

        for i in jsonString[searchStart...].indices {
            let char = jsonString[i]

            if escapeNext {
                escapeNext = false
                continue
            }

            if char == "\\" {
                escapeNext = true
                continue
            }

            if char == "\"" {
                inString.toggle()
                continue
            }

            if !inString {
                if char == "{" {
                    braceCount += 1
                } else if char == "}" {
                    braceCount -= 1
                    if braceCount == 0 {
                        valueEnd = jsonString.index(after: i)
                        break
                    }
                }
            }
        }

        guard braceCount == 0 else { return nil }

        let payloadJsonString = String(jsonString[valueStart..<valueEnd])
        return payloadJsonString.data(using: .utf8)
    }
}
