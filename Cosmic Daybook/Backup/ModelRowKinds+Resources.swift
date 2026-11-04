// ModelRowKinds+Resources.swift
// The backup rows of the classroom's documents and resources (a child's
// files, Restock's staples, procedures, the library's files, stories and book
// club packets), as their hand-written DTOs wrote and restored them until
// "Simplify round two", Phase 7 (see ModelRowKinds.swift). The files
// themselves aren't in backups: only each one's path in the app's folder.

import CoreData
import Foundation

public typealias DocumentDTO = ModelRow<DocumentBackupRow>
public typealias SupplyDTO = ModelRow<SupplyBackupRow>
public typealias ProcedureDTO = ModelRow<ProcedureBackupRow>
public typealias ResourceDTO = ModelRow<ResourceBackupRow>
public typealias StoryDTO = ModelRow<StoryBackupRow>
public typealias BookClubPacketDTO = ModelRow<BookClubPacketBackupRow>

/// A file on a child's page; the PDF and this device's bookmark to it aren't
/// backed up. The child is a string across stores, with no link to re-make:
/// it goes out only when it is an id, restores upper-cased, and a row without
/// one clears it. The path goes out only when there is one, and a row without
/// it restores as none (from a backup before v20 the record keeps its own,
/// `BackupFieldsAddedLater`). A record without an `id` goes out with a new
/// one, as one without an upload date goes out dated now.
public enum DocumentBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "Document",
        filling: ["uploadDate"],
        omitting: ["pdfData", "pdfFileBookmark"],
        uuidStrings: ["studentID"],
        computed: [
            .computed(
                "pdfFileRelativePath", .string, of: CDDocument.self,
                read: { $0.pdfFileRelativePath.isEmpty ? nil : .string($0.pdfFileRelativePath) },
                write: { document, value, _ in
                    document.pdfFileRelativePath = if case .string(let path)? = value { path } else { "" }
                }
            )
        ]
    )
}

/// A staple on the Restock shelf. Its category goes out through the typed
/// category (an unknown raw as Other) and restores as Other when it isn't
/// one. The Restock fields (format v37) are missing from older rows:
/// - the low mark, unit and product link leave the record's own then;
/// - the level and source go out as stored, restore as stocked and the
///   office when they aren't one, and leave the record's own when missing;
/// - who set the level, and when, restore only with the level: a row
///   without `levelRaw` leaves all three as they are; one with it sets each,
///   clearing one it lacks (the name to "").
///
/// The retired ordering fields were never backed up. A record without an
/// `id` goes out with a new one, as one without a created or changed date
/// goes out dated now.
public enum SupplyBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "Supply",
        filling: ["createdAt", "modifiedAt"],
        omitting: ["reorderAmount", "isOnOrder", "orderedQuantity", "orderDate"],
        addedLater: ["minimumThreshold", "unit", "urlString"],
        computed: [
            .raw("categoryRaw", of: CDSupply.self, read: { $0.category }, fallback: SupplyCategory.other),
            ResourceRowFields.storedRaw("levelRaw", of: CDSupply.self, kept: true) {
                (RestockLevel(rawValue: $0) ?? .stocked).rawValue
            },
            ResourceRowFields.storedRaw("sourceRaw", of: CDSupply.self, kept: true) {
                (RestockSource(rawValue: $0) ?? .office).rawValue
            },
            ResourceRowFields.withLevel("levelChangedAt", .date) { $0.levelChangedAt.map(ModelValue.date) },
            ResourceRowFields.withLevel("levelChangedByID", .string) { $0.levelChangedByID.map(ModelValue.string) },
            ResourceRowFields.withLevel("levelChangedByName", .string, cleared: .string("")) {
                .string($0.levelChangedByName)
            }
        ]
    )
}

/// One of the classroom's written procedures. Its category goes out through
/// the typed category (an unknown raw as Other) and restores as Other when it
/// isn't one. `relatedProcedureIDs` carries `relatedProcedureIDsRaw` as the
/// list it holds (comma-separated in the store, none for ""). A record
/// without an `id` goes out with a new one, as one without a created or
/// changed date goes out dated now.
public enum ProcedureBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "Procedure",
        filling: ["createdAt", "modifiedAt"],
        omitting: ["relatedProcedureIDsRaw"],
        computed: [
            .raw("categoryRaw", of: CDProcedure.self, read: { $0.category }, fallback: ProcedureCategory.other),
            .computed(
                "relatedProcedureIDs", .strings, of: CDProcedure.self, required: true,
                read: { .strings($0.relatedProcedureIDs) },
                write: { procedure, value, _ in
                    guard case .strings(let ids)? = value else { return }
                    procedure.relatedProcedureIDs = ids
                }
            )
        ]
    )
}

/// A file in the Resources library; this device's bookmark to it and its
/// thumbnail aren't backed up. Read leniently: a row without the title,
/// description, category, path or linked lessons and areas reads it as "",
/// without a size as 0, without tags as none, without `isFavorite` as not a
/// favorite, and without a created or changed date as the moment it is
/// read. The category goes out as stored and restores as Other when it isn't
/// one. A row without `lastViewedAt` clears it. A record without an `id` goes
/// out with a new one, as one without a created or changed date goes out
/// dated now, and one whose tags won't read goes out with none.
public enum ResourceBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "Resource",
        filling: ["createdAt", "modifiedAt", "tags"],
        omitting: ["fileBookmark", "thumbnailData"],
        defaults: [
            "title": .string(""), "descriptionText": .string(""), "fileRelativePath": .string(""),
            "fileSizeBytes": .int(0), "tags": .strings([]), "isFavorite": .bool(false),
            "linkedLessonIDs": .string(""), "linkedAreas": .string("")
        ],
        nowWhenMissing: ["createdAt", "modifiedAt"],
        computed: [
            ResourceRowFields.storedRaw("categoryRaw", of: CDResource.self, defaultWhenMissing: .string("")) {
                (ResourceCategory(rawValue: $0) ?? .other).rawValue
            }
        ]
    )
}

/// A story in the Stories library; its PDF bookmark, thumbnail and made
/// cover aren't backed up. The analysis status goes out and restores as
/// stored. A record without an `id` goes out with a new one, as one without a
/// created or changed date goes out dated now, and one whose themes won't
/// read goes out with none.
public enum StoryBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "Story",
        filling: ["createdAt", "modifiedAt", "themes"],
        omitting: ["pdfFileBookmark", "thumbnailData", "generatedCoverData"]
    )
}

/// A book club's book and its packet; the packet's PDF bookmark and
/// thumbnail aren't backed up. A record without an `id` goes out with a new
/// one, as one without a created or changed date goes out dated now, and one
/// whose themes won't read goes out with none.
public enum BookClubPacketBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "BookClubPacket",
        filling: ["createdAt", "modifiedAt", "themes"],
        omitting: ["packetPDFBookmark", "thumbnailData"]
    )
}

nonisolated private enum ResourceRowFields {
    /// A string attribute holding an enum's raw value, written as stored (a
    /// bad raw goes out as it is) and restored through `normalized`, the old
    /// importers' `Enum(rawValue:) ?? fallback`. A `kept` one may be missing
    /// from a row, which then leaves the record's own.
    static func storedRaw<Object: NSManagedObject>(
        _ key: String,
        of type: Object.Type,
        kept: Bool = false,
        defaultWhenMissing: ModelValue? = nil,
        restoring normalized: @escaping @MainActor @Sendable (String) -> String
    ) -> ModelField {
        .computed(
            key, .string, of: type, required: !kept, kept: kept, defaultWhenMissing: defaultWhenMissing,
            read: { ($0.value(forKey: key) as? String).map(ModelValue.string) },
            write: { object, value, _ in
                guard case .string(let raw)? = value else { return }
                object.setValue(normalized(raw), forKey: key)
            }
        )
    }

    /// Who set a staple's level, or when: written as stored, and restored
    /// only with the level. A row without `levelRaw` (one from before v37)
    /// leaves it as it is; one with it sets it, or `cleared` when the row
    /// has none.
    static func withLevel(
        _ key: String,
        _ kind: ModelField.Kind,
        cleared: ModelValue? = nil,
        read: @escaping @MainActor @Sendable (CDSupply) -> ModelValue?
    ) -> ModelField {
        .computed(
            key, kind, of: CDSupply.self, read: read,
            write: { supply, value, row in
                guard row["levelRaw"] != nil else { return }
                supply.setValue((value ?? cleared)?.storedValue, forKey: key)
            }
        )
    }
}
