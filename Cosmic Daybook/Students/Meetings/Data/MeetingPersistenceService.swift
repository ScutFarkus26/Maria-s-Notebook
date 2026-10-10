import Foundation
import CoreData

// MARK: - Meeting Persistence Service

/// Meeting drafts (one JSON blob per child in UserDefaults) and meeting history (Core Data).
enum MeetingPersistenceService {
    // MARK: - Current Meeting Data

    /// A child's meeting in progress, kept between launches until it is completed or cleared.
    ///
    /// The optional fields belong to the Meetings workflow; the student
    /// record's Meetings tab leaves them nil, and a nil field keeps whatever
    /// the stored draft already has (see `saveCurrent`).
    struct CurrentMeetingData: Codable, Equatable {
        var isCompleted: Bool = false
        var reflectionText: String = ""
        var focusText: String = ""
        var requestsText: String = ""
        var guideNotesText: String = ""
        var nextMeetingDate: Date?

        // Focus checklist draft persistence
        var pendingFocusTexts: [String]?
        var resolvedFocusIDs: [String]?
        var droppedFocusIDs: [String]?

        // Work review draft persistence (keyed by workID uuidString)
        var workReviewDrafts: [String: String]?
        var reviewedWorkIDs: [String]?

        /// Catalog lessons asked for, as uuidStrings; they go to the inbox on Complete.
        var requestLessonIDs: [String]?

        /// Work the guide chose to re-present, as uuidStrings; on Complete each
        /// one's lesson goes back in the inbox as a second pass.
        var representWorkIDs: [String]?
        /// Work the guide marked ready for the next lesson, as uuidStrings; on
        /// Complete each one's next lesson goes On Deck.
        var readyWorkIDs: [String]?
        /// The `WorkLogService` receipts of the statuses this meeting's work
        /// cards set, keyed by workID uuidString, oldest first, so Clear,
        /// Rest or another outcome can take them back after a relaunch.
        /// Absent in drafts saved before 2026-10-09.
        var closeTokens: [String: [MeetingCloseToken]]?

        var isEmpty: Bool {
            reflectionText.trimmed().isEmpty &&
            focusText.trimmed().isEmpty &&
            requestsText.trimmed().isEmpty &&
            guideNotesText.trimmed().isEmpty &&
            (pendingFocusTexts ?? []).allSatisfy { $0.trimmed().isEmpty } &&
            (resolvedFocusIDs ?? []).isEmpty &&
            (droppedFocusIDs ?? []).isEmpty &&
            (workReviewDrafts ?? [:]).values.allSatisfy { $0.trimmed().isEmpty } &&
            (reviewedWorkIDs ?? []).isEmpty &&
            (requestLessonIDs ?? []).isEmpty &&
            (representWorkIDs ?? []).isEmpty &&
            (readyWorkIDs ?? []).isEmpty &&
            (closeTokens ?? [:]).isEmpty
        }

        /// `self` with every nil workflow field taken from `stored`.
        func keepingWorkflowFields(of stored: CurrentMeetingData) -> CurrentMeetingData {
            var merged = self
            merged.pendingFocusTexts = pendingFocusTexts ?? stored.pendingFocusTexts
            merged.resolvedFocusIDs = resolvedFocusIDs ?? stored.resolvedFocusIDs
            merged.droppedFocusIDs = droppedFocusIDs ?? stored.droppedFocusIDs
            merged.workReviewDrafts = workReviewDrafts ?? stored.workReviewDrafts
            merged.reviewedWorkIDs = reviewedWorkIDs ?? stored.reviewedWorkIDs
            merged.requestLessonIDs = requestLessonIDs ?? stored.requestLessonIDs
            merged.representWorkIDs = representWorkIDs ?? stored.representWorkIDs
            merged.readyWorkIDs = readyWorkIDs ?? stored.readyWorkIDs
            merged.closeTokens = closeTokens ?? stored.closeTokens
            return merged
        }
    }

    // MARK: - Draft Keys

    static let draftKeyPrefix = "MeetingsDraft."

    static func draftKey(_ studentID: UUID) -> String {
        draftKeyPrefix + studentID.uuidString
    }

    /// The ten per-field keys drafts used before they became one blob.
    private static let legacySuffixes = [
        ".reflection", ".focus", ".requests", ".guideNotes", ".nextMeetingDate",
        ".pendingFocusTexts", ".resolvedFocusIDs", ".droppedFocusIDs",
        ".workReviewDrafts", ".reviewedWorkIDs"
    ]

    private static let legacyKeyPrefix = "StudentMeetings.current."

    private static func legacyPrefix(_ studentID: UUID) -> String {
        legacyKeyPrefix + studentID.uuidString
    }

    // MARK: - Load Current

    /// The child's draft, or an empty one. A draft still in the old per-field
    /// keys is moved into the blob (or dropped when empty) the first time it is read.
    static func loadCurrent(studentID: UUID, defaults: UserDefaults = .standard) -> CurrentMeetingData {
        if let data = defaults.data(forKey: draftKey(studentID)),
           let draft = try? JSONDecoder().decode(CurrentMeetingData.self, from: data) {
            return draft
        }
        guard let legacy = loadLegacy(studentID: studentID, defaults: defaults) else {
            return CurrentMeetingData()
        }
        removeLegacy(studentID: studentID, defaults: defaults)
        write(legacy, studentID: studentID, defaults: defaults)
        return legacy
    }

    private static func loadLegacy(studentID: UUID, defaults d: UserDefaults) -> CurrentMeetingData? {
        let prefix = legacyPrefix(studentID)
        guard legacySuffixes.contains(where: { d.object(forKey: prefix + $0) != nil }) else { return nil }
        return CurrentMeetingData(
            isCompleted: false,
            reflectionText: d.string(forKey: prefix + ".reflection") ?? "",
            focusText: d.string(forKey: prefix + ".focus") ?? "",
            requestsText: d.string(forKey: prefix + ".requests") ?? "",
            guideNotesText: d.string(forKey: prefix + ".guideNotes") ?? "",
            nextMeetingDate: d.object(forKey: prefix + ".nextMeetingDate") as? Date,
            pendingFocusTexts: d.stringArray(forKey: prefix + ".pendingFocusTexts"),
            resolvedFocusIDs: d.stringArray(forKey: prefix + ".resolvedFocusIDs"),
            droppedFocusIDs: d.stringArray(forKey: prefix + ".droppedFocusIDs"),
            workReviewDrafts: d.dictionary(forKey: prefix + ".workReviewDrafts") as? [String: String],
            reviewedWorkIDs: d.stringArray(forKey: prefix + ".reviewedWorkIDs")
        )
    }

    private static func removeLegacy(studentID: UUID, defaults: UserDefaults) {
        let prefix = legacyPrefix(studentID)
        for suffix in legacySuffixes {
            defaults.removeObject(forKey: prefix + suffix)
        }
    }

    // MARK: - Save Current

    /// Stores the child's draft; an empty draft removes the key rather than
    /// leaving an empty one behind. Nil workflow fields keep the stored values.
    static func saveCurrent(studentID: UUID, data: CurrentMeetingData, defaults: UserDefaults = .standard) {
        let merged = data.keepingWorkflowFields(of: loadCurrent(studentID: studentID, defaults: defaults))
        write(merged, studentID: studentID, defaults: defaults)
    }

    private static func write(_ draft: CurrentMeetingData, studentID: UUID, defaults: UserDefaults) {
        let key = draftKey(studentID)
        let hadDraft = defaults.object(forKey: key) != nil
        if draft.isEmpty && draft.nextMeetingDate == nil && !draft.isCompleted {
            defaults.removeObject(forKey: key)
        } else if let data = try? JSONEncoder().encode(draft) {
            defaults.set(data, forKey: key)
        }
        if hadDraft != (defaults.object(forKey: key) != nil) {
            NotificationCenter.default.post(name: .meetingDraftsDidChange, object: nil)
        }
    }

    // MARK: - Clear Current

    /// Removes the child's draft, old keys included.
    static func clearCurrent(studentID: UUID, defaults: UserDefaults = .standard) {
        let hadDraft = defaults.object(forKey: draftKey(studentID)) != nil
        defaults.removeObject(forKey: draftKey(studentID))
        removeLegacy(studentID: studentID, defaults: defaults)
        if hadDraft {
            NotificationCenter.default.post(name: .meetingDraftsDidChange, object: nil)
        }
    }

    // MARK: - Draft Presence

    /// Whether the child has a stored draft (in the blob key).
    static func hasDraft(studentID: UUID, defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: draftKey(studentID)) != nil
    }

    /// Children with a draft in progress, for the queue's pencil. Moves any
    /// draft still in the old per-field keys into its blob first, so only the
    /// blob keys need looking at.
    static func studentsWithDrafts(defaults: UserDefaults = .standard) -> Set<UUID> {
        let keys = defaults.dictionaryRepresentation().keys
        let legacyIDs = Set(keys.compactMap { key -> UUID? in
            guard key.hasPrefix(legacyKeyPrefix) else { return nil }
            return UUID(uuidString: String(key.dropFirst(legacyKeyPrefix.count).prefix(36)))
        })
        for id in legacyIDs {
            _ = loadCurrent(studentID: id, defaults: defaults)
        }
        return Set(defaults.dictionaryRepresentation().keys.compactMap { key -> UUID? in
            guard key.hasPrefix(draftKeyPrefix) else { return nil }
            return UUID(uuidString: String(key.dropFirst(draftKeyPrefix.count)))
        })
    }

    // MARK: - Save to History

    /// Saves current meeting data to Core Data history.
    ///
    /// - Parameters:
    ///   - studentID: CDStudent ID
    ///   - data: Current meeting data
    ///   - context: Managed object context
    ///   - save: False leaves the save to a caller that files more with the
    ///     entry and needs it all to land in one save (the Meetings workflow).
    /// - Returns: The created CDStudentMeeting, or nil if data was empty
    @discardableResult
    static func saveToHistory(
        studentID: UUID, data: CurrentMeetingData, context: NSManagedObjectContext, save: Bool = true
    ) -> CDStudentMeeting? {
        let trimmedReflection = data.reflectionText.trimmed()
        let trimmedFocus = data.focusText.trimmed()
        let trimmedRequests = data.requestsText.trimmed()
        let trimmedGuide = data.guideNotesText.trimmed()

        // Anything at all held in the meeting counts — a focus item ticked
        // off or a work item reviewed is a meeting even with no notes.
        guard !data.isEmpty else { return nil }

        let entry = CDStudentMeeting(context: context)
        entry.studentIDUUID = studentID
        entry.date = Date()
        entry.completed = data.isCompleted
        entry.reflection = trimmedReflection
        entry.focus = trimmedFocus
        entry.requests = trimmedRequests
        entry.guideNotes = trimmedGuide
        if save { context.safeSave() }
        return entry
    }

    // MARK: - Migrate History

    /// Migrates legacy history from UserDefaults to SwiftData.
    ///
    /// - Parameters:
    ///   - studentID: CDStudent ID
    ///   - existingMeetings: Existing SwiftData meetings (to check if migration needed)
    ///   - context: Model context
    static func migrateHistoryIfNeeded(
        studentID: UUID, existingMeetings: [CDStudentMeeting], context: NSManagedObjectContext
    ) {
        // If we already have SwiftData meetings for this student, skip migration
        if !existingMeetings.isEmpty { return }

        let historyKey = "StudentMeetings.history.\(studentID.uuidString)"
        let d = UserDefaults.standard
        guard let data = d.data(forKey: historyKey) else { return }

        do {
            let decoded = try JSONDecoder().decode([LegacyMeetingEntry].self, from: data)
            var inserted = 0
            for entry in decoded {
                let m = CDStudentMeeting(context: context)
                m.studentIDUUID = studentID
                m.date = entry.date
                m.completed = entry.completed
                m.reflection = entry.reflection
                m.focus = entry.focus
                m.requests = entry.requests
                m.guideNotes = entry.guideNotes
                inserted += 1
            }
            if inserted > 0 {
                context.safeSave()
            }
            d.removeObject(forKey: historyKey)
        } catch {
            // If decoding fails, leave defaults as-is
        }
    }

    // MARK: - Legacy Types

    private struct LegacyMeetingEntry: Identifiable, Codable {
        let id: UUID
        let date: Date
        let completed: Bool
        let reflection: String
        let focus: String
        let requests: String
        let guideNotes: String
    }
}
