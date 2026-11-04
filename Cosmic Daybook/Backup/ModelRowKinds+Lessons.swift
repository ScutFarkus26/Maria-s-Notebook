// ModelRowKinds+Lessons.swift
// The backup rows of lessons and what hangs off them (assignments,
// presentations, sample work), as their hand-written DTOs wrote and restored
// them until "Simplify round two", Phase 7 (see ModelRowKinds.swift).

import CoreData
import Foundation

public typealias LessonDTO = ModelRow<LessonBackupRow>
public typealias LessonAssignmentDTO = ModelRow<LessonAssignmentBackupRow>
public typealias LessonPresentationDTO = ModelRow<LessonPresentationBackupRow>
public typealias SampleWorkDTO = ModelRow<SampleWorkBackupRow>

/// A lesson in the guide's albums; a record with no `id` isn't backed up.
/// Read leniently: a row without a name, area, sequence, section or write-up
/// reads it as "", without an `orderInSequence` as 0. The fields added in
/// formats v9 to v25 (the album fields, the overrides, the sort index, the
/// album page and confidence, the key-lesson flag, the pages file and primary
/// attachment) leave the record's own when a row lacks them; the parsha,
/// Great Lesson, derived-from, story and album links are cleared then. The
/// Pages bookmark is this device's own. The old row's `createdAt` and
/// `updatedAt` were always written as nil and never restored (the model has
/// neither), so they're no longer read at all.
public enum LessonBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "Lesson",
        omitting: ["pagesFileBookmark"],
        addedLater: [
            "pagesFileRelativePath", "primaryAttachmentID", "suggestedFollowUpWork", "sourceRaw", "personalKindRaw",
            "defaultWorkKindRaw", "materials", "purpose", "ageRange", "teacherNotes", "prerequisiteLessonIDs",
            "relatedLessonIDs", "lessonFormatRaw", "sortIndex", "requiresPracticeOverride",
            "requiresConfirmationOverride", "albumPageIndex", "albumLinkConfidence", "isKeyLesson"
        ],
        uuidStrings: ["primaryAttachmentID"],
        defaults: [
            "name": .string(""), "area": .string(""), "sequence": .string(""), "orderInSequence": .int(0),
            "section": .string(""), "writeUp": .string("")
        ],
        dropsRecordsWithoutID: true
    )
}

/// A lesson planned for, or given to, some children. A row whose `lessonID`
/// isn't an id is passed over on restore; one that is restores it upper-cased
/// (it goes out as stored). `studentIDs` restores as the ids that parse,
/// upper-cased, and reads as none when a row lacks it; a state that isn't one
/// restores as a draft (it too goes out as stored). Read leniently: the
/// practice flags read as false and the follow-up work and notes as "" when a
/// row lacks them. `manuallyUnblocked` and `confirmedStudentIDs` (v19) leave
/// the record's own when a row lacks them. The old importer also looked the
/// lesson up to set `lesson`, which only writes `lessonID` again: the same id.
/// The day mirror and group key aren't backed up.
public enum LessonAssignmentBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "LessonAssignment",
        filling: ["createdAt", "modifiedAt"],
        omitting: ["scheduledForDay", "studentGroupKeyPersisted", "_studentIDsData", "_confirmedStudentIDsData"],
        addedLater: ["manuallyUnblocked"],
        renaming: ["migratedFromLegacyID": "migratedFromStudentLessonID"],
        defaults: [
            "needsPractice": .bool(false), "needsAnotherPresentation": .bool(false),
            "followUpWork": .string(""), "notes": .string("")
        ],
        computed: [
            LessonRowFields.storedRaw("stateRaw", of: CDLessonAssignment.self) {
                (LessonAssignmentState(rawValue: $0) ?? .draft).rawValue
            },
            .computed(
                "lessonID", .string, of: CDLessonAssignment.self, required: true,
                read: { .string($0.lessonID) },
                write: { assignment, value, _ in
                    guard case .string(let text)? = value, let id = UUID(uuidString: text) else { return }
                    assignment.lessonID = id.uuidString
                }
            ),
            .computed(
                "studentIDs", .strings, of: CDLessonAssignment.self, required: true,
                defaultWhenMissing: .strings([]),
                read: { .strings($0.studentIDs) },
                write: { assignment, value, _ in
                    guard case .strings(let ids)? = value else { return }
                    assignment.studentIDs = ids.compactMap(UUID.init(uuidString:)).map(\.uuidString)
                }
            ),
            .computed(
                "confirmedStudentIDs", .strings, of: CDLessonAssignment.self, kept: true,
                read: { .strings($0.confirmedStudentIDs) },
                write: { assignment, value, _ in
                    if case .strings(let ids)? = value { assignment.confirmedStudentIDs = ids }
                }
            )
        ],
        restoresRow: { values in
            if case .string(let text)? = values["lessonID"] { UUID(uuidString: text) != nil } else { false }
        }
    )
}

/// One child's record of a lesson given. A state that isn't one restores as
/// presented (it goes out as stored). A record without a presentation date
/// goes out dated now, as one without an `id` gets a new one.
public enum LessonPresentationBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "LessonPresentation",
        filling: ["createdAt", "presentedAt"],
        computed: [
            LessonRowFields.storedRaw("stateRaw", of: CDLessonPresentation.self) {
                (LessonPresentationState(rawValue: $0) ?? .presented).rawValue
            }
        ]
    )
}

/// A lesson's sample follow-up work. A kind that isn't one restores as a
/// practice lesson (it goes out as stored); a lesson that can't be found
/// leaves the link as it is.
public enum SampleWorkBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "SampleWork",
        filling: ["createdAt"],
        computed: [
            LessonRowFields.storedRaw("workKindRaw", of: CDSampleWork.self) {
                (WorkKind(rawValue: $0) ?? .practiceLesson).rawValue
            }
        ],
        parentIDs: ["lessonID": "lesson"],
        parents: [ParentLink(key: "lessonID", relationship: "lesson")]
    )
}

nonisolated private enum LessonRowFields {
    /// A string attribute holding an enum's raw value, written as stored (a
    /// bad raw goes out as it is) and restored through `restoring`, the old
    /// importers' `Enum(rawValue:) ?? fallback`.
    static func storedRaw<Object: NSManagedObject>(
        _ key: String,
        of type: Object.Type,
        restoring normalized: @escaping @MainActor @Sendable (String) -> String
    ) -> ModelField {
        .computed(
            key, .string, of: type, required: true,
            read: { ($0.value(forKey: key) as? String).map(ModelValue.string) },
            write: { object, value, _ in
                guard case .string(let raw)? = value else { return }
                object.setValue(normalized(raw), forKey: key)
            }
        )
    }
}
