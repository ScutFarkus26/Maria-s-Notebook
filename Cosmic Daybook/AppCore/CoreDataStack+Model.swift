import CoreData
import OSLog

extension CoreDataStack {
    // MARK: - Shared Model

    nonisolated static let modelName = "CosmicDaybook"

    /// MainActor-isolated like the rest of the type, so no lock is needed:
    /// `sharedModel()` is only ever reached from `init`.
    private static var _sharedModel: NSManagedObjectModel?

    /// The one `NSManagedObjectModel` instance this process ever uses.
    ///
    /// Every stack shares it — CloudKit, cached-split, unified, in-memory,
    /// Sample Class. Loading a second copy leaves two `NSEntityDescription`s
    /// claiming each generated class, and Core Data then gives up:
    ///
    ///     warning: Multiple NSEntityDescriptions claim the NSManagedObject
    ///     subclass 'TodoItemEntity' so +entity is unable to disambiguate.
    ///     error: +[TodoItemEntity entity] Failed to find a unique match
    ///
    /// `+entity` returns nil, SwiftUI's `@FetchRequest` builds a request with
    /// no entity, and the app dies on `NSInvalidArgumentException: A fetch
    /// request must have an entity`. A launch where the fallback chain builds
    /// three stacks in a row hit this on 2026-08-25 — which is exactly the
    /// launch that most needed to reach the database-error screen instead.
    ///
    /// Configurations are assigned here, once, because a model becomes
    /// immutable as soon as a coordinator uses it. Stores that want every
    /// entity (unified, in-memory) pass `configuration: nil`, which means the
    /// default configuration — still the model's full entity set.
    static func sharedModel() throws -> NSManagedObjectModel {
        if let existing = _sharedModel { return existing }

        guard let modelURL = Bundle.main.url(forResource: modelName, withExtension: "momd"),
              let cachedModel = NSManagedObjectModel(contentsOf: modelURL) else {
            throw CoreDataStackError.modelNotFound(modelName)
        }
        // Copy: NSManagedObjectModel(contentsOf:) can hand back an instance
        // from its own cache, and assigning configurations would mutate that.
        let model = cachedModel.copy() as! NSManagedObjectModel  // swiftlint:disable:this force_cast
        validateEntityRouting(model: model)
        assignEntitiesToConfigurations(model: model)
        _sharedModel = model
        return model
    }

    // MARK: - Store Configurations

    /// Configuration name for the private (per-teacher) store.
    nonisolated static let privateConfiguration = "Private"
    /// Configuration name for the shared (classroom) store.
    nonisolated static let sharedConfiguration = "Shared"

    // MARK: - Entity Routing

    /// Entities stored in the shared (classroom) store.
    /// These are owned by the lead guide and shared via CKShare with assistants.
    nonisolated static let sharedEntityNames: Set<String> = [
        "Student",
        "Lesson",
        "LessonAttachment",
        "LessonPresentation",
        "Track",
        "TrackStep",
        "SequenceTrack",
        "StudentTrackEnrollment",
        "Procedure",
        "Supply",
        "SupplyTransaction",
        "Schedule",
        "ScheduleSlot",
        "CommunityTopic",
        "ProposedSolution",
        "CommunityAttachment",
        "ClassroomJob",
        "JobAssignment",
        "NoteTemplate",
        "MeetingTemplate",
        "TodoTemplate",
        "Resource",
        "NonSchoolDay",
        "SchoolDayOverride",
        "GoingOut",
        "GoingOutChecklistItem",
        "CalendarNote",
        "SampleWork",
        "SampleWorkStep",
        "ClassroomMembership",
        "Story",
        "BookClubPacket",
        // Moved out of the private store so a shared classroom participant
        // (the assistant) can write attendance. Its former Note relationship
        // is now a string FK, since a relationship cannot cross stores.
        "AttendanceRecord"
    ]

    /// Entities stored in the private (per-teacher) store.
    /// Each teacher has their own copy of these records.
    nonisolated static let privateEntityNames: Set<String> = [
        "Note",
        "NoteStudentLink",
        "WorkModel",
        "WorkStep",
        "WorkCheckIn",
        "WorkParticipantEntity",
        "WorkCompletionRecord",
        "PracticeSession",
        "LessonAssignment",
        "StudentMeeting",
        "ScheduledMeeting",
        "Project",
        "ProjectSession",
        "ProjectAssignmentTemplate",
        "ProjectRole",
        "ProjectTemplateWeek",
        "ProjectWeekRoleAssignment",
        "Reminder",
        "CalendarEvent",
        "TodoItem",
        "TodoSubtask",
        "TodayAgendaOrder",
        "Issue",
        "IssueAction",
        "DevelopmentSnapshot",
        "PlanningRecommendation",
        "Document",
        "YearPlanEntry",
        "LessonSequenceSettings",
        "ParentCommunication",
        "Guardian",
        "MeetingWorkReview",
        "StudentFocusItem",
        "DayPad",
        "BookClubSession",
        "BookClubMeeting",
        "LessonRecallCheck",
        "AlbumBookmark",
        "AlbumPageNote",
        "AlbumRecentVisit",
        "AlbumReadingPosition",
        "AlbumHighlight",
        "AlbumPageInk"
    ]

    /// Entities left in the model on purpose, belonging to no store.
    ///
    /// These are the Transition Planner, Work Cycle, Prep Checklist and
    /// Initiative features, removed end to end on 2026-06-11. No Swift code
    /// references their `CD*` classes, so nothing reads or writes them.
    ///
    /// They stay in the model deliberately. The CloudKit schema is
    /// additive-only, and dropping entities from a mirrored model forces
    /// re-mirroring — the route to the "empty database on launch" failure.
    /// Dormant schema is the cheaper of the two.
    ///
    /// Reviving one of these features means deleting its name from here and
    /// routing it properly; `Phase8PreTests` fails if a name is in both this
    /// set and a routing list.
    nonisolated static let dormantTombstoneEntities: Set<String> = [
        "Initiative",
        "PrepChecklist",
        "PrepChecklistCompletion",
        "PrepChecklistItem",
        "TransitionChecklistItem",
        "TransitionPlan",
        "WorkCycleEntry",
        "WorkCycleSession"
    ]

    // MARK: - Entity Routing

    /// Assigns entities to Private/Shared configurations in the managed object model.
    ///
    /// Canonical NSPersistentCloudKitContainer sharing pattern: classroom-level
    /// entities (Students, Lessons, Tracks, …) live in BOTH configurations so
    /// they can be routed to either store at runtime.
    ///
    /// - On the **lead-guide** device, new classroom records go to the
    ///   `.private`-scope private store (private.sqlite) — Core Data routes new
    ///   inserts to the first store that contains the entity, and we order
    ///   `persistentStoreDescriptions` as `[privateDesc, sharedDesc]`. The
    ///   lead-guide-owned classroom data must live in `.private` scope for
    ///   `container.share(_:to:)` to succeed; `.shared` scope is reserved for
    ///   data the user has accepted *from other users*.
    /// - On the **assistant** device, accepted classroom shares land in the
    ///   `.shared`-scope shared store (shared.sqlite) via
    ///   `container.acceptShareInvitations(into:)`. The same entity types are
    ///   available there too.
    ///
    /// Teacher-private entities (Notes, Work, Attendance, etc.) remain
    /// exclusive to the Private configuration.
    private static func assignEntitiesToConfigurations(model: NSManagedObjectModel) {
        let allEntities = model.entities

        let sharedEntities = allEntities.filter { sharedEntityNames.contains($0.name ?? "") }
        let privateOnlyEntities = allEntities.filter { privateEntityNames.contains($0.name ?? "") }

        // Shared configuration: classroom entities only (receive-shares side).
        model.setEntities(sharedEntities, forConfigurationName: sharedConfiguration)

        // Private configuration: teacher-private + classroom entities. Classroom
        // entities appearing in both configs is what enables the canonical
        // two-store sharing pattern.
        let privateConfigEntities = privateOnlyEntities + sharedEntities
        model.setEntities(privateConfigEntities, forConfigurationName: privateConfiguration)

        let classroomCount = sharedEntities.count
        let privateExclusiveCount = privateOnlyEntities.count
        let privateConfigCount = privateConfigEntities.count
        let routingMsg = "Entity routing: \(privateConfigCount) in private " +
            "(\(privateExclusiveCount) exclusive + \(classroomCount) classroom), " +
            "\(classroomCount) in shared"
        logger.info("\(routingMsg, privacy: .public)")
    }

    /// Validates that all entity names in our routing tables exist in the model.
    /// Logs warnings for mismatches but does not crash — allows the app to continue.
    private static func validateEntityRouting(model: NSManagedObjectModel) {
        let modelEntityNames = Set(model.entities.compactMap(\.name))
        let routedNames = sharedEntityNames.union(privateEntityNames)

        let missingFromModel = routedNames.subtracting(modelEntityNames)
        if !missingFromModel.isEmpty {
            logger.warning("Entity routing references entities not in model: \(missingFromModel)")
        }

        // Warn only about the unexpected. Warning about the known tombstones on
        // every launch trained everyone to scroll past the message, which is the
        // opposite of what a tripwire is for — and it reads as a data-loss
        // scare to anyone meeting it for the first time.
        let unrouted = modelEntityNames
            .subtracting(routedNames)
            .subtracting(dormantTombstoneEntities)
        if !unrouted.isEmpty {
            logger.warning("Model entities not assigned to any store: \(unrouted)")
        }

        let missingTombstones = dormantTombstoneEntities.subtracting(modelEntityNames)
        if !missingTombstones.isEmpty {
            logger.warning("Tombstone entities no longer in the model — prune the list: \(missingTombstones)")
        }
    }
}
