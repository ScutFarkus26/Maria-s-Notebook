// BackupPredatedValues.swift
// What a restore keeps on the records it updates when the backup is older
// than some of their attributes.

import CoreData
import Foundation

/// Optional attributes added to a backed-up type after its first format, with
/// the first format whose rows always carry them.
///
/// A row from an older backup has no value for such an attribute, which reads
/// exactly like "nil" — so a merge restore used to clear it on every record it
/// updated (a v28 backup wiped every attendance note, a v36 one every need's
/// staple). A restore from a format below the version here leaves the
/// record's own value instead. Non-optional attributes added later need no
/// line: their importers set them only when the row has them
/// (`ModelRowSpec.addedLater`, `if let` in the hand-written importers).
///
/// When a format bump adds an optional attribute to a type that older backups
/// already carry, add it here with the new format's number. An attribute that
/// joined in the middle of a format (no bump) gets the next format, the first
/// whose every backup has it; the older format then keeps the record's value
/// only where its row had nothing.
nonisolated enum BackupFieldsAddedLater {
    static let attributes: [String: [String: Int]] = [
        "AttendanceRecord": [
            // Added 2026-08-30 without a bump, so v23 is the first that always has them.
            "recordedBy": 23, "recordedByID": 23, "recordedByName": 23, "modifiedAt": 23,
            "note": 29,
            "markedAt": 32,
            "leftAt": 33,
            "leavesAt": 35,
            "returnedAt": 36, "statusBeforeLeavingRaw": 36
        ],
        "OrderItem": ["supplyID": 37, "addedByID": 37],
        // How attendance goes to the school (schema 18). The two non-optional
        // fields with an "email" default are `addedLater` in their row specs.
        "AttendanceEmailSettings": ["parentLockerSite": 40],
        "ScheduledMeeting": ["purpose": 24],
        // Lesson, Student, Note, LessonPresentation, TodoItem and Document
        // fields that joined during v17–v19 (June to August 2026, no bumps).
        "Lesson": [
            "parshaKey": 20, "greatLessonRaw": 20, "derivedFromLessonID": 20, "parentStoryID": 20,
            "albumID": 22, "albumLessonTitle": 22
        ],
        "Student": [
            "nickname": 20, "dateWithdrawn": 20, "previousLevelRaw": 20, "dateLastPromoted": 20,
            "parentLockerID": 40
        ],
        "Note": [
            "reportedBy": 20, "reporterName": 20, "communityTopicID": 20, "schoolDayOverrideID": 20,
            "studentTrackEnrollmentID": 20, "goingOutID": 20
        ],
        "LessonPresentation": [
            "followUpActionRaw": 20, "followUpEvidenceRaw": 20, "followUpNote": 20, "followUpResolutionRaw": 20,
            "followUpResolvedAt": 20, "followUpReviewAt": 20, "followUpSupportRaw": 20, "followUpUpdatedAt": 20
        ],
        "TodoItem": ["moodRaw": 20, "tideLink": 41],
        // Non-optional, but exported as nil when empty: "" is its "missing".
        "Document": ["pdfFileRelativePath": 20]
    ]

    /// The attributes of `entityName` that a backup of `formatVersion` can't carry.
    static func missing(from formatVersion: Int, in entityName: String) -> [String] {
        guard let added = attributes[entityName] else { return [] }
        return added.compactMap { formatVersion < $0.value ? $0.key : nil }.sorted()
    }

    /// An attribute added later whose value an older backup's row already
    /// holds under another name.
    struct StandIn: Sendable, Equatable {
        /// The attribute the older rows lack.
        let attribute: String
        /// The attribute of the same row read in its place.
        let from: String
        /// The first format whose rows carry `attribute` themselves.
        let version: Int
    }

    /// Unlike `attributes`, these are filled from the row rather than kept
    /// from the record: a lesson file in a backup from before v43 was last
    /// changed when it was attached, as far as that backup knows, and the rest
    /// of its row (name, file, size) is restored as of then too.
    static let standIns: [String: [StandIn]] = [
        "LessonAttachment": [StandIn(attribute: "modifiedAt", from: "attachedAt", version: 43)]
    ]

    /// The stand-ins a backup of `formatVersion` needs for `entityName`'s rows.
    static func standIns(from formatVersion: Int, in entityName: String) -> [StandIn] {
        (standIns[entityName] ?? []).filter { formatVersion < $0.version }
    }
}

/// The values a restore keeps because its backup predates them: noted as each
/// record is found to update (`BackupEntityIndex.existing`), put back once the
/// import is done wherever the importer left the attribute at its model
/// default — what a row without the attribute always leaves.
///
/// Main-actor state of one restore, like the index that holds it.
final class BackupPredatedValues {
    private let formatVersion: Int
    /// Per record, the values it had before the restore touched it. The first
    /// look wins: a record found twice is noted once, before any import.
    private var kept: [NSManagedObjectID: [String: Any]] = [:]
    private var order: [NSManagedObject] = []
    private var missingByEntity: [String: [String]] = [:]

    init(formatVersion: Int) {
        self.formatVersion = formatVersion
    }

    /// `rows` with each attribute this backup predates read from its stand-in
    /// (`BackupFieldsAddedLater.standIns`) where the row has none of its own.
    func standingIn<Kind: ModelRowKind>(for rows: [ModelRow<Kind>]) -> [ModelRow<Kind>] {
        let standIns = BackupFieldsAddedLater.standIns(from: formatVersion, in: Kind.spec.entityName)
        guard !standIns.isEmpty else { return rows }
        return rows.map { row in
            var row = row
            for standIn in standIns where row.values[standIn.attribute] == nil {
                row.values[standIn.attribute] = row.values[standIn.from]
            }
            return row
        }
    }

    /// Notes `object`'s values for the attributes this backup predates.
    func remember(_ object: NSManagedObject) {
        guard let entityName = object.entity.name else { return }
        let names = missing(in: entityName)
        guard !names.isEmpty, kept[object.objectID] == nil else { return }
        var values: [String: Any] = [:]
        for name in names {
            if let value = object.value(forKey: name) { values[name] = value }
        }
        kept[object.objectID] = values
        order.append(object)
    }

    /// Puts each noted value back where the restore left the model default.
    /// Returns how many values it put back.
    @discardableResult
    func putBack() -> Int {
        var restored = 0
        for object in order where !object.isDeleted {
            guard let values = kept[object.objectID] else { continue }
            let attributes = object.entity.attributesByName
            for (name, value) in values {
                let now = object.value(forKey: name)
                guard Self.isDefault(now, of: attributes[name]) else { continue }
                object.setValue(value, forKey: name)
                restored += 1
            }
        }
        kept = [:]
        order = []
        return restored
    }

    private func missing(in entityName: String) -> [String] {
        if let names = missingByEntity[entityName] { return names }
        let names = BackupFieldsAddedLater.missing(from: formatVersion, in: entityName)
        missingByEntity[entityName] = names
        return names
    }

    /// True when `value` is what the model gives the attribute by default
    /// (nil for an optional attribute without one, "" for a required string
    /// without one).
    private static func isDefault(_ value: Any?, of attribute: NSAttributeDescription?) -> Bool {
        var fallback = attribute?.defaultValue
        if fallback == nil, let attribute, !attribute.isOptional, attribute.attributeType == .stringAttributeType {
            fallback = ""
        }
        switch (value, fallback) {
        case (nil, nil): return true
        case let (value?, fallback?): return (value as AnyObject).isEqual(fallback)
        default: return false
        }
    }
}
