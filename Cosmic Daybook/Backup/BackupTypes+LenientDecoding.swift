import Foundation

// MARK: - Lenient Decoding
//
// These DTOs decode by hand so a row missing a field still restores: a missing
// string reads as "", a missing count as 0. Plain `Codable` would throw instead.
// (Until 2026-09-30 they also read the pre-v16 names `subject` / `group` /
// `subheading`; the reader accepts only v17+, so no readable backup has them.)

/// String-keyed CodingKey that lets us look up arbitrary JSON field names at
/// decode time without enumerating every field in a fixed enum.
nonisolated private struct FieldKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

nonisolated private extension KeyedDecodingContainer where Key == FieldKey {
    /// The string at `key`, or "" when the row has none.
    func decodeString(_ key: String) throws -> String {
        try decodeIfPresent(String.self, forKey: FieldKey(key)) ?? ""
    }

    /// The integer at `key`, or 0 when the row has none.
    func decodeInt(_ key: String) throws -> Int {
        try decodeIfPresent(Int.self, forKey: FieldKey(key)) ?? 0
    }
}

// MARK: - SequenceTrackDTO

nonisolated extension SequenceTrackDTO {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FieldKey.self)
        self.id = try c.decode(UUID.self, forKey: FieldKey("id"))
        self.area = try c.decodeString("area")
        self.sequence = try c.decodeString("sequence")
        self.isSequential = try c.decodeIfPresent(Bool.self, forKey: FieldKey("isSequential")) ?? true
        self.isExplicitlyDisabled = try c.decodeIfPresent(Bool.self, forKey: FieldKey("isExplicitlyDisabled")) ?? false
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: FieldKey("createdAt")) ?? Date()
    }
}

// MARK: - ResourceDTO

nonisolated extension ResourceDTO {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FieldKey.self)
        self.id = try c.decode(UUID.self, forKey: FieldKey("id"))
        self.title = try c.decodeString("title")
        self.descriptionText = try c.decodeString("descriptionText")
        self.categoryRaw = try c.decodeString("categoryRaw")
        self.fileRelativePath = try c.decodeString("fileRelativePath")
        self.fileSizeBytes = try c.decodeIfPresent(Int64.self, forKey: FieldKey("fileSizeBytes")) ?? 0
        self.tags = try c.decodeIfPresent([String].self, forKey: FieldKey("tags")) ?? []
        self.isFavorite = try c.decodeIfPresent(Bool.self, forKey: FieldKey("isFavorite")) ?? false
        self.lastViewedAt = try c.decodeIfPresent(Date.self, forKey: FieldKey("lastViewedAt"))
        self.linkedLessonIDs = try c.decodeString("linkedLessonIDs")
        self.linkedAreas = try c.decodeString("linkedAreas")
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: FieldKey("createdAt")) ?? Date()
        self.modifiedAt = try c.decodeIfPresent(Date.self, forKey: FieldKey("modifiedAt")) ?? Date()
    }
}
