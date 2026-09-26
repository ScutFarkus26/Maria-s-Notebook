import Foundation

nonisolated extension PreferencesDTO {
    /// The archive's `preferences.json`: the whole dictionary as one JSON
    /// document (preferences are small, so no NDJSON), keys sorted.
    func archiveJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
