import Foundation

// MARK: - Legacy Key Backward-Compat Decoding
//
// Backups created before format v16 used the field names `subject` / `group` /
// `subheading` / `orderInGroup` / `groupTracks` / `lessonSubheadingSnapshot`.
// v16 renamed the lesson hierarchy to area / sequence / section. To keep older
// backups restorable, the affected DTOs decode either spelling — new names win
// when both are present.

/// String-keyed CodingKey that lets us look up arbitrary JSON field names at
/// decode time without enumerating every legacy spelling in a fixed enum.
private struct LegacyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

private extension KeyedDecodingContainer where Key == LegacyKey {
    func decode<T: Decodable>(
        _ type: T.Type,
        primary: String,
        legacy: String
    ) throws -> T where T: ExpressibleByStringLiteral {
        if let v = try decodeIfPresent(type, forKey: LegacyKey(primary)) { return v }
        if let v = try decodeIfPresent(type, forKey: LegacyKey(legacy)) { return v }
        return "" as! T // swiftlint:disable:this force_cast
    }

    func decodeInt(primary: String, legacy: String) throws -> Int {
        if let v = try decodeIfPresent(Int.self, forKey: LegacyKey(primary)) { return v }
        if let v = try decodeIfPresent(Int.self, forKey: LegacyKey(legacy)) { return v }
        return 0
    }

    func decodeOptionalString(primary: String, legacy: String) throws -> String? {
        if let v = try decodeIfPresent(String.self, forKey: LegacyKey(primary)) { return v }
        return try decodeIfPresent(String.self, forKey: LegacyKey(legacy))
    }
}

// MARK: - LessonDTO

extension LessonDTO {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LegacyKey.self)
        self.id = try c.decode(UUID.self, forKey: LegacyKey("id"))
        self.name = try c.decode(String.self, primary: "name", legacy: "name")
        self.area = try c.decode(String.self, primary: "area", legacy: "subject")
        self.sequence = try c.decode(String.self, primary: "sequence", legacy: "group")
        self.orderInSequence = try c.decodeInt(primary: "orderInSequence", legacy: "orderInGroup")
        self.section = try c.decode(String.self, primary: "section", legacy: "subheading")
        self.writeUp = try c.decode(String.self, primary: "writeUp", legacy: "writeUp")
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: LegacyKey("createdAt"))
        self.updatedAt = try c.decodeIfPresent(Date.self, forKey: LegacyKey("updatedAt"))
        self.pagesFileRelativePath = try c.decodeIfPresent(String.self, forKey: LegacyKey("pagesFileRelativePath"))
        self.primaryAttachmentID = try c.decodeIfPresent(UUID.self, forKey: LegacyKey("primaryAttachmentID"))
        self.suggestedFollowUpWork = try c.decodeIfPresent(String.self, forKey: LegacyKey("suggestedFollowUpWork"))
        self.sourceRaw = try c.decodeIfPresent(String.self, forKey: LegacyKey("sourceRaw"))
        self.personalKindRaw = try c.decodeIfPresent(String.self, forKey: LegacyKey("personalKindRaw"))
        self.defaultWorkKindRaw = try c.decodeIfPresent(String.self, forKey: LegacyKey("defaultWorkKindRaw"))
        self.materials = try c.decodeIfPresent(String.self, forKey: LegacyKey("materials"))
        self.purpose = try c.decodeIfPresent(String.self, forKey: LegacyKey("purpose"))
        self.ageRange = try c.decodeIfPresent(String.self, forKey: LegacyKey("ageRange"))
        self.teacherNotes = try c.decodeIfPresent(String.self, forKey: LegacyKey("teacherNotes"))
        self.prerequisiteLessonIDs = try c.decodeIfPresent(String.self, forKey: LegacyKey("prerequisiteLessonIDs"))
        self.relatedLessonIDs = try c.decodeIfPresent(String.self, forKey: LegacyKey("relatedLessonIDs"))
        self.parshaKey = try c.decodeIfPresent(String.self, forKey: LegacyKey("parshaKey"))
        self.greatLessonRaw = try c.decodeIfPresent(String.self, forKey: LegacyKey("greatLessonRaw"))
        self.lessonFormatRaw = try c.decodeIfPresent(String.self, forKey: LegacyKey("lessonFormatRaw"))
        self.sortIndex = try c.decodeIfPresent(Int.self, forKey: LegacyKey("sortIndex"))
        self.derivedFromLessonID = try c.decodeIfPresent(String.self, forKey: LegacyKey("derivedFromLessonID"))
        self.parentStoryID = try c.decodeIfPresent(String.self, forKey: LegacyKey("parentStoryID"))
        self.requiresPracticeOverride = try c.decodeIfPresent(String.self, forKey: LegacyKey("requiresPracticeOverride"))
        self.requiresConfirmationOverride = try c.decodeIfPresent(
            String.self, forKey: LegacyKey("requiresConfirmationOverride")
        )
    }
}

// MARK: - LessonAssignmentDTO

extension LessonAssignmentDTO {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LegacyKey.self)
        self.id = try c.decode(UUID.self, forKey: LegacyKey("id"))
        self.createdAt = try c.decode(Date.self, forKey: LegacyKey("createdAt"))
        self.modifiedAt = try c.decode(Date.self, forKey: LegacyKey("modifiedAt"))
        self.stateRaw = try c.decode(String.self, forKey: LegacyKey("stateRaw"))
        self.scheduledFor = try c.decodeIfPresent(Date.self, forKey: LegacyKey("scheduledFor"))
        self.presentedAt = try c.decodeIfPresent(Date.self, forKey: LegacyKey("presentedAt"))
        self.lessonID = try c.decode(String.self, forKey: LegacyKey("lessonID"))
        self.studentIDs = try c.decodeIfPresent([String].self, forKey: LegacyKey("studentIDs")) ?? []
        self.lessonTitleSnapshot = try c.decodeIfPresent(String.self, forKey: LegacyKey("lessonTitleSnapshot"))
        self.lessonSectionSnapshot = try c.decodeOptionalString(
            primary: "lessonSectionSnapshot",
            legacy: "lessonSubheadingSnapshot"
        )
        self.needsPractice = try c.decodeIfPresent(Bool.self, forKey: LegacyKey("needsPractice")) ?? false
        self.needsAnotherPresentation = try c.decodeIfPresent(
            Bool.self,
            forKey: LegacyKey("needsAnotherPresentation")
        ) ?? false
        self.followUpWork = try c.decodeIfPresent(String.self, forKey: LegacyKey("followUpWork")) ?? ""
        self.notes = try c.decodeIfPresent(String.self, forKey: LegacyKey("notes")) ?? ""
        self.trackID = try c.decodeIfPresent(String.self, forKey: LegacyKey("trackID"))
        self.trackStepID = try c.decodeIfPresent(String.self, forKey: LegacyKey("trackStepID"))
        self.migratedFromLegacyID = try c.decodeIfPresent(String.self, forKey: LegacyKey("migratedFromLegacyID"))
        self.migratedFromPresentationID = try c.decodeIfPresent(
            String.self,
            forKey: LegacyKey("migratedFromPresentationID")
        )
        self.manuallyUnblocked = try c.decodeIfPresent(Bool.self, forKey: LegacyKey("manuallyUnblocked"))
    }
}

// MARK: - SequenceTrackDTO

extension SequenceTrackDTO {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LegacyKey.self)
        self.id = try c.decode(UUID.self, forKey: LegacyKey("id"))
        self.area = try c.decode(String.self, primary: "area", legacy: "subject")
        self.sequence = try c.decode(String.self, primary: "sequence", legacy: "group")
        self.isSequential = try c.decodeIfPresent(Bool.self, forKey: LegacyKey("isSequential")) ?? true
        self.isExplicitlyDisabled = try c.decodeIfPresent(Bool.self, forKey: LegacyKey("isExplicitlyDisabled")) ?? false
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: LegacyKey("createdAt")) ?? Date()
    }
}

// MARK: - ResourceDTO

extension ResourceDTO {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LegacyKey.self)
        self.id = try c.decode(UUID.self, forKey: LegacyKey("id"))
        self.title = try c.decode(String.self, primary: "title", legacy: "title")
        self.descriptionText = try c.decode(String.self, primary: "descriptionText", legacy: "descriptionText")
        self.categoryRaw = try c.decode(String.self, primary: "categoryRaw", legacy: "categoryRaw")
        self.fileRelativePath = try c.decode(String.self, primary: "fileRelativePath", legacy: "fileRelativePath")
        self.fileSizeBytes = try c.decodeIfPresent(Int64.self, forKey: LegacyKey("fileSizeBytes")) ?? 0
        self.tags = try c.decodeIfPresent([String].self, forKey: LegacyKey("tags")) ?? []
        self.isFavorite = try c.decodeIfPresent(Bool.self, forKey: LegacyKey("isFavorite")) ?? false
        self.lastViewedAt = try c.decodeIfPresent(Date.self, forKey: LegacyKey("lastViewedAt"))
        self.linkedLessonIDs = try c.decode(String.self, primary: "linkedLessonIDs", legacy: "linkedLessonIDs")
        self.linkedAreas = try c.decode(String.self, primary: "linkedAreas", legacy: "linkedSubjects")
        self.createdAt = try c.decodeIfPresent(Date.self, forKey: LegacyKey("createdAt")) ?? Date()
        self.modifiedAt = try c.decodeIfPresent(Date.self, forKey: LegacyKey("modifiedAt")) ?? Date()
    }
}
