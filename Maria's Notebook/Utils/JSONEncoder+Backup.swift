import Foundation

extension JSONEncoder {
    /// Creates a JSON encoder configured for backup operations
    /// - Returns: Configured encoder with ISO8601 dates and sorted keys
    static func backupConfigured() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return encoder
    }
}

extension JSONDecoder {
    /// Creates a JSON decoder configured for backup operations
    /// - Returns: Configured decoder with ISO8601 dates
    static func backupConfigured() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
