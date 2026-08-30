import Foundation
import CoreData
import Testing
@testable import Maria_s_Notebook

// MARK: - Field-Level Backup Coverage
//
// `BackupCoverageTests` guarantees every ENTITY is backed up; this suite
// guarantees every ATTRIBUTE of every backed-up entity survives a full
// export → import round-trip. It exists because the entity-level test has
// repeatedly passed while live transformers silently dropped fields
// (Note.includeInReport, Lesson album fields, NoteDTO.tags/needsFollowUp,
// LessonAssignment.confirmedStudentIDs, …).
//
// How it works:
//  1. One instance of every backed-up entity is inserted into a single
//     in-memory stack, and EVERY model attribute is populated with a
//     distinct non-default value (`FieldValueGenerator`). Cross-entity ID
//     attributes are wired to the seeded sibling so importer guards resolve.
//  2. The whole context is exported through the LIVE transformer path
//     (`BackupService.collectPayload` → `BackupWriter.serializeEntries`) and
//     re-imported into a fresh stack (`BackupImporter.reconstructPayload` →
//     `importPayload`) — the same v18/v19 serialization layer real backups
//     use, minus the entity-agnostic AEA file container.
//  3. Every attribute is compared source-vs-restored. Attributes that are
//     INTENTIONALLY not round-tripped (binary blobs, EventKit sync IDs,
//     orphaned schema, reshaped storage) must be listed in the spec's
//     `skips` with a reason — and a staleness test keeps those lists honest.
//
// Adding a new entity to the backup? The spec-completeness test fails until
// you add a `FieldSpec` for it below — one line if nothing needs special
// handling; every one of its attributes is then covered automatically.

// MARK: - Spec Model

/// Per-entity description of how to populate and verify its attributes.
private struct FieldSpec {
    let entityName: String

    /// Attribute → raw value to store instead of the generated one. Use for
    /// fields that must hold a VALID domain value to survive parsing
    /// (enum raw strings, structured JSON, bounded integers).
    var overrides: [String: Any] = [:]

    /// Attribute → entity name whose seeded instance's `id` should be stored.
    /// Supplements `FieldCoverage.defaultWires` (the name-based convention).
    var wires: [String: String] = [:]

    /// Attribute → documented reason it is EXPECTED not to round-trip.
    /// Every entry here is a conscious, reviewed data-loss decision.
    var skips: [String: String] = [:]

    /// Attribute → semantic comparison for reshaped storage (e.g. binary
    /// blobs whose bytes differ after re-encode but whose decoded value must
    /// match). The attribute is excluded from the generic comparison.
    var checks: [String: @MainActor (_ source: NSManagedObject, _ restored: NSManagedObject) -> Bool] = [:]

    /// Runs after generic population for typed setup the KVC layer can't do
    /// (e.g. `note.scope = …`). Receives the seeded-object registry.
    var customize: (@MainActor (_ object: NSManagedObject, _ seeded: [String: NSManagedObject]) -> Void)?

    init(
        _ entityName: String,
        overrides: [String: Any] = [:],
        wires: [String: String] = [:],
        skips: [String: String] = [:],
        checks: [String: @MainActor (NSManagedObject, NSManagedObject) -> Bool] = [:],
        customize: (@MainActor (NSManagedObject, [String: NSManagedObject]) -> Void)? = nil
    ) {
        self.entityName = entityName
        self.overrides = overrides
        self.wires = wires
        self.skips = skips
        self.checks = checks
        self.customize = customize
    }
}

// MARK: - Value Generation

private enum FieldValueGenerator {
    /// Deterministic-ish distinct values; whole-second dates so ISO8601
    /// (second precision) round-trips exactly.
    static func value(
        for attribute: NSAttributeDescription,
        entityName: String,
        ordinal: Int
    ) -> Any? {
        let name = attribute.name
        switch attribute.attributeType {
        case .UUIDAttributeType:
            return UUID()
        case .stringAttributeType:
            // ID-suffixed strings hold UUID strings app-wide; several
            // transformers/importers `UUID(uuidString:)`-parse them.
            if name.hasSuffix("ID") || name.hasSuffix("Id") {
                return UUID().uuidString
            }
            return "fc-\(entityName).\(name)"
        case .dateAttributeType:
            return Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(ordinal * 60))
        case .booleanAttributeType:
            let defaultBool = (attribute.defaultValue as? Bool) ?? false
            return !defaultBool
        case .integer16AttributeType, .integer32AttributeType, .integer64AttributeType:
            let defaultInt = (attribute.defaultValue as? Int) ?? 0
            let candidate = 2 + (ordinal % 89)
            return candidate == defaultInt ? candidate + 1 : candidate
        case .doubleAttributeType, .floatAttributeType:
            return 1.25 + Double(ordinal)
        case .binaryDataAttributeType:
            return Data("fc-\(entityName).\(name)".utf8)
        case .transformableAttributeType:
            // The model's transformables are [String] unless a spec overrides.
            return ["fc-\(name)-1", "fc-\(name)-2"] as NSArray
        default:
            return nil
        }
    }

    /// Compare with normalization for encoding artifacts: dates survive at
    /// second precision, numbers compare as NSNumber, arrays element-wise.
    static func matches(_ lhs: Any?, _ rhs: Any?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (l as Date, r as Date):
            return abs(l.timeIntervalSince1970 - r.timeIntervalSince1970) < 1.0
        case let (l as NSNumber, r as NSNumber):
            return l == r
        case let (l as NSObject, r as NSObject):
            return l.isEqual(r)
        default:
            return false
        }
    }
}

// MARK: - Engine

@MainActor
private enum FieldCoverage {
    /// Convention: ID-named string/UUID attributes point at the seeded
    /// instance of the referenced entity, so importer existence/parse guards
    /// resolve exactly like a real backup. Spec `wires` add to / override this.
    static let defaultWires: [String: String] = [
        "studentID": "Student",
        "searchIndexStudentID": "Student",
        "assignedToStudentID": "Student",
        "leaderStudentID": "Student",
        "lessonID": "Lesson",
        "coveredByLessonID": "Lesson",
        "derivedFromLessonID": "Lesson",
        "lessonTemplateID": "Lesson",
        "workID": "WorkModel",
        "linkedWorkItemID": "WorkModel",
        "noteID": "Note",
        "goingOutID": "GoingOut",
        "projectID": "Project",
        "packetID": "BookClubPacket",
        "issueID": "Issue",
        "scheduleID": "Schedule",
        "jobID": "ClassroomJob",
        "trackID": "Track",
        "trackStepID": "TrackStep",
        "meetingID": "StudentMeeting",
        "createdInMeetingID": "StudentMeeting",
        "resolvedInMeetingID": "StudentMeeting",
        "communityTopicID": "CommunityTopic",
        "schoolDayOverrideID": "SchoolDayOverride",
        "studentTrackEnrollmentID": "StudentTrackEnrollment",
        "presentationID": "LessonPresentation",
        "parentStoryID": "Story",
        "promotedAssignmentID": "LessonAssignment",
        "primaryAttachmentID": "LessonAttachment"
    ]

    /// The seeded object's `id`, rendered for the referencing attribute's type.
    static func wiredValue(
        target: NSManagedObject,
        attributeType: NSAttributeType
    ) -> Any? {
        guard let id = target.value(forKey: "id") else { return nil }
        switch (id, attributeType) {
        case let (uuid as UUID, .stringAttributeType):
            return uuid.uuidString
        case let (uuid as UUID, .UUIDAttributeType):
            return uuid
        case let (string as String, .stringAttributeType):
            return string
        default:
            return nil
        }
    }

    struct SeededEntity {
        let spec: FieldSpec
        let object: NSManagedObject
        /// Attribute → value as stored at save time (post-customize snapshot).
        var storedValues: [String: Any?] = [:]
    }

    /// Inserts one instance of every spec'd entity, populates all attributes,
    /// wires cross-entity IDs, runs customizations, snapshots stored values.
    static func seed(
        specs: [FieldSpec],
        into context: NSManagedObjectContext
    ) throws -> [String: SeededEntity] {
        // Phase 1: insert everything so wiring can reference any sibling.
        var registry: [String: NSManagedObject] = [:]
        for spec in specs {
            registry[spec.entityName] = NSEntityDescription.insertNewObject(
                forEntityName: spec.entityName, into: context
            )
        }

        // Phase 2: populate attributes.
        var seeded: [String: SeededEntity] = [:]
        var ordinal = 0
        for spec in specs {
            guard let object = registry[spec.entityName] else { continue }
            for (name, attribute) in object.entity.attributesByName.sorted(by: { $0.key < $1.key }) {
                ordinal += 1
                let value: Any?
                if let override = spec.overrides[name] {
                    value = override
                } else if let targetName = spec.wires[name] ?? Self.defaultWires[name],
                          let target = registry[targetName],
                          let wired = wiredValue(target: target, attributeType: attribute.attributeType) {
                    value = wired
                } else {
                    value = FieldValueGenerator.value(
                        for: attribute, entityName: spec.entityName, ordinal: ordinal
                    )
                }
                if let value {
                    object.setValue(value, forKey: name)
                }
            }
            spec.customize?(object, registry)
            seeded[spec.entityName] = SeededEntity(spec: spec, object: object)
        }

        // Phase 3: snapshot exactly what Core Data holds after customize.
        for spec in specs {
            guard var entry = seeded[spec.entityName] else { continue }
            for name in entry.object.entity.attributesByName.keys {
                entry.storedValues[name] = entry.object.value(forKey: name)
            }
            seeded[spec.entityName] = entry
        }
        return seeded
    }

    /// Round-trips the context through the live v18/v19 serialization layer:
    /// collectPayload (live transformers) → NDJSON encode → reconstructPayload
    /// → importPayload into a fresh in-memory stack. Bypasses only the
    /// entity-agnostic AEA file container (covered by Backup2RoundTripTests).
    static func roundTrip(_ context: NSManagedObjectContext) async throws -> CoreDataStack {
        let service = BackupService()
        let payload = service.collectPayload(viewContext: context)
        let entries = try BackupWriter.serializeEntries(from: payload)
        let manifest = BackupArchiveManifest(
            formatVersion: BackupWriter.formatVersion, createdAt: Date(),
            appVersion: "", appBuild: "", device: "", entityCounts: [:], originStores: [:]
        )
        let decoded = BackupReader.DecodedBackup(
            manifest: manifest, entries: entries, preferences: payload.preferences
        )
        let (reconstructed, warnings) = BackupImporter.reconstructPayload(from: decoded)
        #expect(warnings.isEmpty, "Field-coverage round-trip decoded with warnings: \(warnings)")

        let destStack = try CoreDataTestHelpers.makeInMemoryStack()
        _ = try await service.importPayload(
            payload: reconstructed,
            envelopeFormatVersion: BackupWriter.formatVersion,
            envelopeEncrypted: false,
            envelopeCreatedAt: Date(),
            envelopeFileName: "field-coverage-roundtrip",
            envelopeEntityCounts: manifest.entityCounts,
            viewContext: destStack.viewContext,
            mode: .merge,
            appRouter: AppRouter.shared,
            progress: { _, _ in }
        )
        return destStack
    }

    /// Finds the restored counterpart of a seeded object by its `id`.
    static func restoredObject(
        for seededObject: NSManagedObject,
        entityName: String,
        in context: NSManagedObjectContext
    ) throws -> NSManagedObject? {
        guard let id = seededObject.value(forKey: "id") else { return nil }
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        switch id {
        case let uuid as UUID:
            request.predicate = NSPredicate(format: "id == %@", uuid as CVarArg)
        case let string as String:
            request.predicate = NSPredicate(format: "id == %@", string)
        default:
            return nil
        }
        request.fetchLimit = 1
        return try context.fetch(request).first
    }
}

// MARK: - Suite

@Suite("Backup field-level coverage")
@MainActor
final class BackupFieldCoverageTests {

    // MARK: Spec Table
    //
    // One entry per backed-up entity. `skips` document every attribute that
    // deliberately does not round-trip — each is a reviewed decision, not an
    // oversight. Keep reasons specific; the staleness test verifies the
    // attribute still exists.

    /// Reason strings reused across specs.
    private static let bookmarkReason =
        "security-scoped file bookmark — device-local by nature, excluded from backups by design"
    private static let blobReason =
        "binary payload intentionally excluded from backups (see writer warning: attachments/documents not included)"
    private static let eventKitReason =
        "device-local EventKit sync identifier — intentionally not backed up (re-links on the destination device)"

    private static let specs: [FieldSpec] = [
        FieldSpec(
            "Student",
            overrides: [
                // Parsed into StudentDTO.Level on export — must be a valid, non-default rawValue.
                // "Adolescent" pins the newest case: a non-exhaustive mapping would clamp it to lower.
                "levelRaw": "Adolescent",
                // Exported via `nextLessonUUIDs` (compactMap UUID(uuidString:)) — elements must parse.
                "nextLessons": [UUID().uuidString, UUID().uuidString] as NSArray
            ]
        ),
        FieldSpec(
            "Lesson",
            skips: ["pagesFileBookmark": bookmarkReason]
        ),
        FieldSpec(
            "LessonAssignment",
            // Importer parses stateRaw via LessonAssignmentState(rawValue:).
            overrides: ["stateRaw": "scheduled"],
            skips: [
                "scheduledForDay": "start-of-day mirror of scheduledFor (see schedule(for:)); "
                    + "re-derived after restore, reads use scheduledFor",
                "studentGroupKeyPersisted": "denormalized cache of studentIDs; studentGroupKey "
                    + "falls back to the computed key when empty (DenormalizedSchedulable)"
            ],
            customize: { object, _ in
                // JSON-[String] blobs behind typed accessors; importer re-parses
                // the elements as UUIDs, so they must be valid UUID strings.
                guard let assignment = object as? CDLessonAssignment else { return }
                assignment.studentIDs = [UUID().uuidString]
                assignment.confirmedStudentIDs = [UUID().uuidString]
            }
        ),
        FieldSpec(
            "Note",
            skips: [
                "categoryRaw": "legacy category field, superseded by tags — not exported by design",
                "transitionPlanID": "orphaned schema: no @NSManaged accessor and no app usage (removed feature)"
            ],
            checks: [
                // scopeBlob is JSON without deterministic key order — byte equality
                // fails on a faithful round-trip. Compare the decoded scope instead.
                "scopeBlob": { source, restored in
                    (source as? CDNote)?.scope == (restored as? CDNote)?.scope
                }
            ],
            customize: { object, seeded in
                // scopeBlob is JSON-encoded NoteScope; setting `scope` also syncs
                // searchIndexStudentID + scopeIsAll, keeping all three consistent.
                guard let note = object as? CDNote else { return }
                let studentID = (seeded["Student"]?.value(forKey: "id") as? UUID) ?? UUID()
                note.scope = .student(studentID)
            }
        ),
        FieldSpec("NonSchoolDay"),
        FieldSpec("SchoolDayOverride"),
        FieldSpec("StudentMeeting"),
        FieldSpec(
            "CommunityTopic",
            customize: { object, _ in
                // _tagsData is a JSON-[String] blob behind the `tags` accessor.
                (object as? CDCommunityTopicEntity)?.tags = ["fc-topic-tag-1", "fc-topic-tag-2"]
            }
        ),
        FieldSpec("ProposedSolution"),
        FieldSpec(
            "CommunityAttachment",
            // Importer parses kindRaw via CommunityAttachmentKind(rawValue:).
            overrides: ["kindRaw": "photo"],
            skips: ["data": blobReason]
        ),
        FieldSpec(
            "AttendanceRecord",
            // Exported as parsed enums (a.status.rawValue) — must be valid, non-default rawValues.
            overrides: ["statusRaw": "present", "absenceReasonRaw": "sick"]
        ),
        FieldSpec("WorkCompletionRecord"),
        FieldSpec("Project"),
        FieldSpec("ProjectSession"),
        FieldSpec("ProjectRole"),
        FieldSpec(
            "WorkModel",
            // Importer parses statusRaw via WorkStatus(rawValue:).
            overrides: ["statusRaw": "review"],
            skips: [
                "legacyContractID": "pre-migration bookkeeping (WorkModelDTO deliberately omits it)",
                "legacyStudentLessonID": "pre-migration bookkeeping (WorkModelDTO deliberately omits it)"
            ]
        ),
        FieldSpec(
            "WorkCheckIn",
            // Importer parses statusRaw via WorkCheckInStatus(rawValue:) — rawValues are capitalized.
            overrides: ["statusRaw": "Completed"]
        ),
        FieldSpec("WorkStep"),
        FieldSpec("WorkParticipantEntity"),
        FieldSpec("PracticeSession"),
        FieldSpec(
            "LessonAttachment",
            skips: [
                "fileBookmark": bookmarkReason,
                "thumbnailData": blobReason
            ]
        ),
        FieldSpec(
            "LessonPresentation",
            // Importer parses stateRaw via LessonPresentationState(rawValue:).
            overrides: ["stateRaw": "practicing"]
        ),
        FieldSpec("LessonRecallCheck"),
        FieldSpec(
            "SampleWork",
            // Importer parses workKindRaw via WorkKind(rawValue:).
            overrides: ["workKindRaw": "followUpAssignment"]
        ),
        FieldSpec("SampleWorkStep"),
        FieldSpec(
            "NoteTemplate",
            skips: [
                "categoryRaw": "legacy category field — importer maps it into tags "
                    + "(TagHelper.tagFromNoteCategory) instead of restoring it"
            ]
        ),
        FieldSpec("MeetingTemplate"),
        FieldSpec(
            "Reminder",
            skips: [
                "eventKitReminderID": eventKitReason,
                "eventKitCalendarID": eventKitReason,
                "lastSyncedAt": eventKitReason
            ]
        ),
        FieldSpec(
            "CalendarEvent",
            skips: [
                "eventKitEventID": eventKitReason,
                "eventKitCalendarID": eventKitReason,
                "lastSyncedAt": eventKitReason
            ]
        ),
        FieldSpec("Track"),
        FieldSpec("TrackStep"),
        FieldSpec("StudentTrackEnrollment"),
        FieldSpec("SequenceTrack"),
        FieldSpec(
            "Document",
            skips: [
                "pdfData": blobReason,
                "pdfFileBookmark": bookmarkReason
            ]
        ),
        FieldSpec(
            "Supply",
            // Importer parses categoryRaw via SupplyCategory(rawValue:).
            overrides: ["categoryRaw": "Math"],
            skips: [
                // Orphaned schema: these exist in the .xcdatamodel but have no
                // @NSManaged accessor and no app usage — there is no data to back up.
                "isOnOrder": "orphaned schema: no @NSManaged accessor, no app usage",
                "unit": "orphaned schema: no @NSManaged accessor, no app usage",
                "minimumThreshold": "orphaned schema: no @NSManaged accessor, no app usage",
                "orderedQuantity": "orphaned schema: no @NSManaged accessor, no app usage",
                "reorderAmount": "orphaned schema: no @NSManaged accessor, no app usage",
                "orderDate": "orphaned schema: no @NSManaged accessor, no app usage"
            ]
        ),
        FieldSpec(
            "Procedure",
            // Importer parses categoryRaw via ProcedureCategory(rawValue:).
            overrides: ["categoryRaw": "Safety & Emergency"]
        ),
        FieldSpec("Schedule"),
        FieldSpec(
            "ScheduleSlot",
            // Importer parses weekdayRaw via Weekday(rawValue:).
            overrides: ["weekdayRaw": "Tuesday"]
        ),
        FieldSpec(
            "Issue",
            // Importer parses all three via their enums.
            overrides: [
                "statusRaw": "Investigating",
                "priorityRaw": "High",
                "categoryRaw": "Behavioral"
            ],
            customize: { object, _ in
                (object as? CDIssue)?.studentIDs = [UUID().uuidString]
            }
        ),
        FieldSpec(
            "IssueAction",
            // Importer parses actionTypeRaw via IssueActionType(rawValue:).
            overrides: ["actionTypeRaw": "Conversation"],
            customize: { object, _ in
                (object as? CDIssueAction)?.participantStudentIDs = [UUID().uuidString]
            }
        ),
        FieldSpec(
            "DevelopmentSnapshot",
            customize: { object, _ in
                // The nine *Data attributes are JSON-[String] blobs behind
                // typed array accessors; export decodes them into DTO arrays.
                guard let snapshot = object as? CDDevelopmentSnapshotEntity else { return }
                snapshot.keyStrengths = ["fc-keyStrengths"]
                snapshot.areasForGrowth = ["fc-areasForGrowth"]
                snapshot.developmentalMilestones = ["fc-developmentalMilestones"]
                snapshot.observedPatterns = ["fc-observedPatterns"]
                snapshot.behavioralTrends = ["fc-behavioralTrends"]
                snapshot.socialEmotionalInsights = ["fc-socialEmotionalInsights"]
                snapshot.recommendedNextLessons = ["fc-recommendedNextLessons"]
                snapshot.suggestedPracticeFocus = ["fc-suggestedPracticeFocus"]
                snapshot.interventionSuggestions = ["fc-interventionSuggestions"]
            }
        ),
        FieldSpec(
            "TodoItem",
            // Importer parses both via TodoPriority / RecurrencePattern.
            overrides: ["priorityRaw": "High", "recurrenceRaw": "Weekly"],
            skips: [
                "notificationID": "device-local UNUserNotificationCenter identifier; "
                    + "notifications are rescheduled on the destination device",
                "initiativeID": "orphaned schema: no @NSManaged accessor and no app usage"
            ]
        ),
        FieldSpec("TodoSubtask"),
        FieldSpec(
            "TodoTemplate",
            overrides: ["priorityRaw": "Medium"]
        ),
        FieldSpec(
            "TodayAgendaOrder",
            // Importer parses itemTypeRaw via AgendaItemType(rawValue:).
            overrides: ["itemTypeRaw": "meeting"]
        ),
        FieldSpec(
            "PlanningRecommendation",
            // Importer DROPS the record if depthLevel isn't a valid PlanningDepth.
            overrides: ["depthLevel": "deep"],
            customize: { object, _ in
                (object as? CDPlanningRecommendation)?.studentIDs = [UUID().uuidString]
            }
        ),
        FieldSpec(
            "Resource",
            // Importer parses categoryRaw via ResourceCategory(rawValue:).
            overrides: ["categoryRaw": "Writing Papers"],
            skips: [
                "fileBookmark": bookmarkReason,
                "thumbnailData": blobReason
            ]
        ),
        FieldSpec("NoteStudentLink"),
        FieldSpec("GoingOut"),
        FieldSpec("GoingOutChecklistItem"),
        FieldSpec("ClassroomJob"),
        FieldSpec("JobAssignment"),
        FieldSpec("CalendarNote"),
        FieldSpec(
            "ScheduledMeeting",
            customize: { object, _ in
                (object as? CDScheduledMeeting)?.participantStudentIDs = [UUID().uuidString]
            }
        ),
        FieldSpec(
            "ClassroomMembership",
            // role is parsed via ClassroomRole(rawValue:).
            overrides: ["roleRaw": "assistant"]
        ),
        FieldSpec("MeetingWorkReview"),
        FieldSpec("StudentFocusItem"),
        FieldSpec("DayPad"),
        FieldSpec("YearPlanEntry"),
        FieldSpec("LessonSequenceSettings"),
        FieldSpec(
            "Story",
            skips: [
                "pdfFileBookmark": bookmarkReason,
                "thumbnailData": blobReason,
                "generatedCoverData": blobReason
            ]
        ),
        FieldSpec(
            "BookClubPacket",
            skips: [
                "packetPDFBookmark": bookmarkReason,
                "thumbnailData": blobReason
            ]
        ),
        FieldSpec("BookClubSession"),
        FieldSpec("BookClubMeeting"),
        FieldSpec(
            "Guardian",
            // relationship is parsed via GuardianRelationship(rawValue:).
            overrides: ["relationshipRaw": "guardian"]
        ),
        FieldSpec(
            "ParentCommunication",
            // communicationType/status are parsed via their raw-value enums;
            // includedItemRefs must hold valid JSON for the includedRefs accessor.
            overrides: [
                "communicationTypeRaw": "monthlyReport",
                "statusRaw": "reviewed",
                "monthKey": "2026-09",
                "includedItemRefs": "[\"note:00000000-0000-0000-0000-000000000001\"]"
            ]
        ),
        FieldSpec("AlbumBookmark"),
        FieldSpec("AlbumPageNote"),
        FieldSpec("AlbumRecentVisit"),
        FieldSpec("AlbumReadingPosition"),
        FieldSpec(
            "AlbumHighlight",
            // rectsData holds JSON [[x, y, width, height]] that the exporter
            // decodes into numbers — arbitrary bytes would decode to no
            // rectangles and the re-encoded blob wouldn't match.
            overrides: ["rectsData": Data("[[10,20,100,12],[10,34,80,12]]".utf8)],
            checks: [
                // Re-encoded on import, so compare the decoded rectangles
                // rather than the bytes.
                "rectsData": { source, restored in
                    (source as? CDAlbumHighlight)?.rects == (restored as? CDAlbumHighlight)?.rects
                }
            ]
        ),
        // Pencil ink is the one binary blob carried through a backup verbatim:
        // unlike thumbnails it is user-authored and cannot be regenerated.
        FieldSpec("AlbumPageInk")
    ]

    // MARK: Tests

    @Test("Every attribute of every backed-up entity survives a round-trip")
    func everyAttributeRoundTrips() async throws {
        let sourceStack = try CoreDataTestHelpers.makeInMemoryStack()
        let ctx = sourceStack.viewContext

        let seeded = try FieldCoverage.seed(specs: Self.specs, into: ctx)
        #expect(CoreDataTestHelpers.save(ctx), "Field-coverage fixture save failed")

        let destStack = try await FieldCoverage.roundTrip(ctx)
        let dctx = destStack.viewContext

        for spec in Self.specs {
            guard let entry = seeded[spec.entityName] else {
                Issue.record("\(spec.entityName): seeding produced no instance")
                continue
            }
            guard let restored = try FieldCoverage.restoredObject(
                for: entry.object, entityName: spec.entityName, in: dctx
            ) else {
                Issue.record(
                    "\(spec.entityName): record was DROPPED by the round-trip (not found by id in the restored store)"
                )
                continue
            }

            for name in entry.object.entity.attributesByName.keys.sorted() {
                if spec.skips[name] != nil { continue }
                if let check = spec.checks[name] {
                    #expect(
                        check(entry.object, restored),
                        "\(spec.entityName).\(name): custom round-trip check failed"
                    )
                    continue
                }
                let expected = entry.storedValues[name] ?? nil
                let actual = restored.value(forKey: name)
                #expect(
                    FieldValueGenerator.matches(expected, actual),
                    """
                    \(spec.entityName).\(name) did not survive the backup round-trip: \
                    stored \(String(describing: expected)), restored \(String(describing: actual)). \
                    Either the live transformer/DTO/importer drops this field (fix it), or the loss \
                    is intentional (add a documented skip to its FieldSpec).
                    """
                )
            }
        }
    }

    @Test("Spec table covers exactly the writer's entity set")
    func specTableIsComplete() {
        let specNames = Self.specs.map(\.entityName)
        let writerNames = BackupWriter.serializedEntityNames

        #expect(
            specNames.count == Set(specNames).count,
            "Duplicate FieldSpec entries: \(Dictionary(grouping: specNames, by: { $0 }).filter { $1.count > 1 }.keys.sorted())"
        )

        let missingSpecs = Set(writerNames).subtracting(specNames)
        #expect(
            missingSpecs.isEmpty,
            "Backed-up entities with NO field-coverage spec (add a FieldSpec — new fields would be unguarded): \(missingSpecs.sorted())"
        )

        let staleSpecs = Set(specNames).subtracting(writerNames)
        #expect(
            staleSpecs.isEmpty,
            "FieldSpecs for entities the writer no longer serializes: \(staleSpecs.sorted())"
        )
    }

    @Test("Skip/override/wire lists reference real attributes")
    func specListsAreNotStale() throws {
        let context = try CoreDataTestHelpers.makeInMemoryStack().viewContext
        guard let model = context.persistentStoreCoordinator?.managedObjectModel else {
            Issue.record("No managed object model available")
            return
        }
        for spec in Self.specs {
            guard let entity = model.entitiesByName[spec.entityName] else {
                Issue.record("FieldSpec entity '\(spec.entityName)' is not in the model")
                continue
            }
            let attributes = Set(entity.attributesByName.keys)
            for (collection, names) in [
                ("skips", Array(spec.skips.keys)),
                ("overrides", Array(spec.overrides.keys)),
                ("wires", Array(spec.wires.keys)),
                ("checks", Array(spec.checks.keys))
            ] {
                for name in names where !attributes.contains(name) {
                    Issue.record(
                        "\(spec.entityName) \(collection) references '\(name)', which is no longer a model attribute — remove or update it"
                    )
                }
            }
        }
    }
}
