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

// MARK: - LessonDTO

nonisolated extension LessonDTO {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FieldKey.self)
        self.id = try c.decode(UUID.self, forKey: FieldKey("id"))
        self.name = try c.decodeString("name")
        self.area = try c.decodeString("area")
        self.sequence = try c.decodeString("sequence")
        self.orderInSequence = try c.decodeInt("orderInSequence")
        self.section = try c.decodeString("section")
        self.writeUp = try c.decodeString("writeUp")
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: FieldKey("createdAt"))
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: FieldKey("updatedAt"))
        self.pagesFileRelativePath = try c.decodeIfPresent(String.self, forKey: FieldKey("pagesFileRelativePath"))
        self.primaryAttachmentID = try c.decodeIfPresent(UUID.self, forKey: FieldKey("primaryAttachmentID"))
        self.suggestedFollowUpWork = try c.decodeIfPresent(String.self, forKey: FieldKey("suggestedFollowUpWork"))
        self.sourceRaw = try c.decodeIfPresent(String.self, forKey: FieldKey("sourceRaw"))
        self.personalKindRaw = try c.decodeIfPresent(String.self, forKey: FieldKey("personalKindRaw"))
        self.defaultWorkKindRaw = try c.decodeIfPresent(String.self, forKey: FieldKey("defaultWorkKindRaw"))
        self.materials = try c.decodeIfPresent(String.self, forKey: FieldKey("materials"))
        self.purpose = try c.decodeIfPresent(String.self, forKey: FieldKey("purpose"))
        self.ageRange = try c.decodeIfPresent(String.self, forKey: FieldKey("ageRange"))
        self.teacherNotes = try c.decodeIfPresent(String.self, forKey: FieldKey("teacherNotes"))
        self.prerequisiteLessonIDs = try c.decodeIfPresent(String.self, forKey: FieldKey("prerequisiteLessonIDs"))
        self.relatedLessonIDs = try c.decodeIfPresent(String.self, forKey: FieldKey("relatedLessonIDs"))
        self.parshaKey = try c.decodeIfPresent(String.self, forKey: FieldKey("parshaKey"))
        self.greatLessonRaw = try c.decodeIfPresent(String.self, forKey: FieldKey("greatLessonRaw"))
        self.lessonFormatRaw = try c.decodeIfPresent(String.self, forKey: FieldKey("lessonFormatRaw"))
        self.sortIndex = try c.decodeIfPresent(Int.self, forKey: FieldKey("sortIndex"))
        self.derivedFromLessonID = try c.decodeIfPresent(String.self, forKey: FieldKey("derivedFromLessonID"))
        self.parentStoryID = try c.decodeIfPresent(String.self, forKey: FieldKey("parentStoryID"))
        self.requiresPracticeOverride = try c.decodeIfPresent(String.self, forKey: FieldKey("requiresPracticeOverride"))
        self.requiresConfirmationOverride = try c.decodeIfPresent(
            String.self, forKey: FieldKey("requiresConfirmationOverride")
        )
        // Teaching-album link (format v22+); absent in older backups.
        self.albumID = try c.decodeIfPresent(String.self, forKey: FieldKey("albumID"))
        self.albumPageIndex = try c.decodeIfPresent(Int.self, forKey: FieldKey("albumPageIndex"))
        self.albumLessonTitle = try c.decodeIfPresent(
            String.self, forKey: FieldKey("albumLessonTitle")
        )
        self.albumLinkConfidence = try c.decodeIfPresent(
            Double.self, forKey: FieldKey("albumLinkConfidence")
        )
        // Three-Year View milestone flag (format v25+); absent in older backups.
        self.isKeyLesson = try c.decodeIfPresent(Bool.self, forKey: FieldKey("isKeyLesson"))
    }
}

// MARK: - LessonAssignmentDTO

nonisolated extension LessonAssignmentDTO {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: FieldKey.self)
        self.id = try c.decode(UUID.self, forKey: FieldKey("id"))
        self.createdAt = try c.decode(Date.self, forKey: FieldKey("createdAt"))
        self.modifiedAt = try c.decode(Date.self, forKey: FieldKey("modifiedAt"))
        self.stateRaw = try c.decode(String.self, forKey: FieldKey("stateRaw"))
        self.scheduledFor = try c.decodeIfPresent(Date.self, forKey: FieldKey("scheduledFor"))
        self.presentedAt = try c.decodeIfPresent(Date.self, forKey: FieldKey("presentedAt"))
        self.lessonID = try c.decode(String.self, forKey: FieldKey("lessonID"))
        self.studentIDs = try c.decodeIfPresent([String].self, forKey: FieldKey("studentIDs")) ?? []
        self.lessonTitleSnapshot = try c.decodeIfPresent(String.self, forKey: FieldKey("lessonTitleSnapshot"))
        self.lessonSectionSnapshot = try c.decodeIfPresent(String.self, forKey: FieldKey("lessonSectionSnapshot"))
        self.needsPractice = try c.decodeIfPresent(Bool.self, forKey: FieldKey("needsPractice")) ?? false
        self.needsAnotherPresentation = try c.decodeIfPresent(
            Bool.self,
            forKey: FieldKey("needsAnotherPresentation")
        ) ?? false
        self.followUpWork = try c.decodeIfPresent(String.self, forKey: FieldKey("followUpWork")) ?? ""
        self.notes = try c.decodeIfPresent(String.self, forKey: FieldKey("notes")) ?? ""
        self.trackID = try c.decodeIfPresent(String.self, forKey: FieldKey("trackID"))
        self.trackStepID = try c.decodeIfPresent(String.self, forKey: FieldKey("trackStepID"))
        self.migratedFromLegacyID = try c.decodeIfPresent(String.self, forKey: FieldKey("migratedFromLegacyID"))
        self.migratedFromPresentationID = try c.decodeIfPresent(
            String.self,
            forKey: FieldKey("migratedFromPresentationID")
        )
        self.manuallyUnblocked = try c.decodeIfPresent(Bool.self, forKey: FieldKey("manuallyUnblocked"))
        self.confirmedStudentIDs = try c.decodeIfPresent([String].self, forKey: FieldKey("confirmedStudentIDs"))
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
