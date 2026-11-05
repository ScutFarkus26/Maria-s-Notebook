// ModelRowKinds+Planning.swift
// The backup rows of the guide's planning records (a child's development
// snapshots, to-dos, Today's order, lesson recommendations and going-out
// checklists), as their hand-written DTOs wrote and restored them until
// "Simplify round two", Phase 7 (see ModelRowKinds.swift). Going-outs
// themselves were already table rows (ModelRowKinds.swift).

import CoreData
import Foundation

public typealias DevelopmentSnapshotDTO = ModelRow<DevelopmentSnapshotBackupRow>
public typealias TodoItemDTO = ModelRow<TodoItemBackupRow>
public typealias TodayAgendaOrderDTO = ModelRow<TodayAgendaOrderBackupRow>
public typealias PlanningRecommendationDTO = ModelRow<PlanningRecommendationBackupRow>
public typealias GoingOutChecklistItemDTO = ModelRow<GoingOutChecklistItemBackupRow>

/// One child's development snapshot. Each of the nine lists carries its
/// `…Data` blob as the typed list (a blob that won't decode goes out as
/// none). The practice quality and independence go out as the typed
/// accessors read them, 0 for none, and restore as 0 when a row lacks them.
/// A record without an `id` goes out with a new one, as one without a date
/// made goes out dated now.
public enum DevelopmentSnapshotBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "DevelopmentSnapshot",
        filling: ["generatedAt"],
        omitting: [
            "keyStrengthsData", "areasForGrowthData", "developmentalMilestonesData", "observedPatternsData",
            "behavioralTrendsData", "socialEmotionalInsightsData", "recommendedNextLessonsData",
            "suggestedPracticeFocusData", "interventionSuggestionsData"
        ],
        computed: [
            PlanningRowFields.list("keyStrengths", \CDDevelopmentSnapshotEntity.keyStrengths),
            PlanningRowFields.list("areasForGrowth", \CDDevelopmentSnapshotEntity.areasForGrowth),
            PlanningRowFields.list("developmentalMilestones", \CDDevelopmentSnapshotEntity.developmentalMilestones),
            PlanningRowFields.list("observedPatterns", \CDDevelopmentSnapshotEntity.observedPatterns),
            PlanningRowFields.list("behavioralTrends", \CDDevelopmentSnapshotEntity.behavioralTrends),
            PlanningRowFields.list("socialEmotionalInsights", \CDDevelopmentSnapshotEntity.socialEmotionalInsights),
            PlanningRowFields.list("recommendedNextLessons", \CDDevelopmentSnapshotEntity.recommendedNextLessons),
            PlanningRowFields.list("suggestedPracticeFocus", \CDDevelopmentSnapshotEntity.suggestedPracticeFocus),
            PlanningRowFields.list("interventionSuggestions", \CDDevelopmentSnapshotEntity.interventionSuggestions),
            PlanningRowFields.number("averagePracticeQuality", \CDDevelopmentSnapshotEntity.averagePracticeQuality),
            PlanningRowFields.number("independenceLevel", \CDDevelopmentSnapshotEntity.independenceLevel)
        ]
    )
}

/// One of the guide's to-dos. Its priority and repeat go out through the
/// typed accessors (an unknown raw as none) and restore as none when they
/// aren't one. The repeat interval, both time estimates and the place's
/// latitude and longitude go out as the typed accessors read them, 0 for
/// none, and restore as 0 when a row lacks them; a row without `isSomeday`
/// or `repeatAfterCompletion` reads it as false. The Tide link (v41) leaves
/// the record's own when a row lacks it, so a restored to-do isn't sent to
/// Tide a second time; a Merge never blanks a link the record has since
/// gained. The notification id is this device's own, and the initiative id
/// was never backed up. A Merge stands by a to-do done here (`ModelRow`'s
/// `rowCompletedAt`). A record without an `id` goes out with a new one, as
/// one without a created date goes out dated now, and one whose children,
/// attachments or tags won't read goes out with none.
public enum TodoItemBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "TodoItem",
        filling: ["createdAt", "studentIDs", "attachmentPaths", "tags"],
        omitting: ["notificationID", "initiativeID"],
        addedLater: ["tideLink"],
        defaults: ["isSomeday": .bool(false), "repeatAfterCompletion": .bool(false)],
        computed: [
            .raw("priorityRaw", of: CDTodoItem.self, read: { $0.priority }, fallback: TodoPriority.none),
            .raw("recurrenceRaw", of: CDTodoItem.self, read: { $0.recurrence }, fallback: RecurrencePattern.none),
            PlanningRowFields.number("customIntervalDays", \CDTodoItem.customIntervalDays),
            PlanningRowFields.number("estimatedMinutes", \CDTodoItem.estimatedMinutes),
            PlanningRowFields.number("actualMinutes", \CDTodoItem.actualMinutes),
            PlanningRowFields.number("locationLatitude", \CDTodoItem.locationLatitude),
            PlanningRowFields.number("locationLongitude", \CDTodoItem.locationLongitude)
        ]
    )
}

/// Where one item sits in Today's order on a day. The item's kind goes out as
/// stored and restores as a lesson when it isn't one. A record without an
/// `id` goes out with a new one, as one without a day goes out dated now and
/// one without an item gets a new item id.
public enum TodayAgendaOrderBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "TodayAgendaOrder",
        filling: ["day", "itemID"],
        computed: [
            .storedRaw("itemTypeRaw", of: CDTodayAgendaOrder.self) {
                (AgendaItemType(rawValue: $0) ?? .lesson).rawValue
            }
        ]
    )
}

/// A lesson the planner recommended for some children. A row whose `lessonID`
/// or `planningSessionID` isn't an id, or whose `depthLevel` isn't a planning
/// depth, is passed over on restore; one that is restores both ids
/// upper-cased (they go out as stored). `studentIDsData` carries the
/// `_studentIDsData` blob as it is; it restores as the ids in it that parse,
/// upper-cased, re-encoded, and a row without it restores as no children (an
/// empty list, not no blob). A record without an `id` goes out with a new
/// one, as one without a created or changed date goes out dated now.
public enum PlanningRecommendationBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "PlanningRecommendation",
        filling: ["createdAt", "modifiedAt"],
        omitting: ["_studentIDsData"],
        computed: [
            PlanningRowFields.idString("lessonID", of: CDPlanningRecommendation.self),
            PlanningRowFields.idString("planningSessionID", of: CDPlanningRecommendation.self),
            .computed(
                "studentIDsData", .data, of: CDPlanningRecommendation.self,
                read: { $0._studentIDsData.map(ModelValue.data) },
                write: { recommendation, value, _ in
                    let blob: Data? = if case .data(let data)? = value { data } else { nil }
                    recommendation.studentIDs = CloudKitStringArrayStorage.decode(from: blob)
                        .compactMap(UUID.init(uuidString:)).map(\.uuidString)
                }
            )
        ],
        restoresRow: { values in
            guard PlanningRowFields.isID(values["lessonID"]), PlanningRowFields.isID(values["planningSessionID"]),
                  case .string(let depth)? = values["depthLevel"] else { return false }
            return PlanningDepth(rawValue: depth) != nil
        }
    )
}

/// One line on a going-out's checklist. A row whose `goingOutID` isn't an id
/// is passed over on restore; one that is restores it upper-cased (it goes
/// out as stored) and files the line under that going-out when it's here
/// (one that isn't leaves the link as it is). A record without an `id` goes
/// out with a new one, as one without a created date goes out dated now.
public enum GoingOutChecklistItemBackupRow: ModelRowKind {
    public static let spec = ModelRowSpec(
        "GoingOutChecklistItem",
        filling: ["createdAt"],
        computed: [PlanningRowFields.idString("goingOutID", of: CDGoingOutChecklistItem.self)],
        parents: [ParentLink(key: "goingOutID", relationship: "goingOut")],
        restoresRow: { PlanningRowFields.isID($0["goingOutID"]) }
    )
}

nonisolated private enum PlanningRowFields {
    /// Whether a row's value is a string holding an id.
    static func isID(_ value: ModelValue?) -> Bool {
        if case .string(let text)? = value { UUID(uuidString: text) != nil } else { false }
    }

    /// A string attribute holding an id, written as stored and restored
    /// upper-cased (the spec's `restoresRow` passes over a row whose value
    /// isn't an id).
    static func idString<Object: NSManagedObject>(_ key: String, of type: Object.Type) -> ModelField {
        .computed(
            key, .string, of: type, required: true,
            read: { ($0.value(forKey: key) as? String).map(ModelValue.string) },
            write: { object, value, _ in
                guard case .string(let text)? = value, let id = UUID(uuidString: text) else { return }
                object.setValue(id.uuidString, forKey: key)
            }
        )
    }

    /// A list kept as a blob, written and restored through its typed list.
    static func list<Object: NSManagedObject>(
        _ key: String,
        _ path: ReferenceWritableKeyPath<Object, [String]> & Sendable
    ) -> ModelField {
        .computed(
            key, .strings, of: Object.self, required: true,
            read: { .strings($0[keyPath: path]) },
            write: { object, value, _ in
                guard case .strings(let list)? = value else { return }
                object[keyPath: path] = list
            }
        )
    }

    /// An optional whole number the old row typed as a number: written as the
    /// typed accessor reads it (0 for none), so it is always there, and
    /// restored as 0 when a row lacks it.
    static func number<Object: NSManagedObject>(
        _ key: String,
        _ path: ReferenceWritableKeyPath<Object, Int64> & Sendable
    ) -> ModelField {
        .computed(
            key, .int, of: Object.self,
            read: { .int(Int($0[keyPath: path])) },
            write: { object, value, _ in
                object[keyPath: path] = if case .int(let number)? = value { Int64(number) } else { 0 }
            }
        )
    }

    /// `number` for an optional decimal.
    static func number<Object: NSManagedObject>(
        _ key: String,
        _ path: ReferenceWritableKeyPath<Object, Double> & Sendable
    ) -> ModelField {
        .computed(
            key, .double, of: Object.self,
            read: { .double($0[keyPath: path]) },
            write: { object, value, _ in
                object[keyPath: path] = if case .double(let number)? = value { number } else { 0 }
            }
        )
    }
}
