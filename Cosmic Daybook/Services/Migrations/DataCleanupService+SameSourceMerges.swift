import Foundation
import CoreData

// MARK: - Same-source merges
//
// Rows that stand for one thing under two ids, which the id-based pass can't
// see. Both kinds come from a store filled by two writers at once — the
// launch code of a freshly reset device and the iCloud download it is still
// receiving (2026-09-28: +33 reminders, +8 calendar events and +7 templates
// from one reset, on top of ~120 template copies from earlier ones):
//
// - Reminders and calendar events are mirrors of Apple items. The EventKit
//   mirror inserted its own row for every item before the download brought
//   the old one down. One EventKit reminder is one row; a calendar event
//   keeps one row per occurrence (a recurring event reports one identifier for
//   all of them), so events fold on identifier + start.
// - Templates were seeded into the empty store beside the notebook's own
//   copies still on their way down. They fold only when every field a guide
//   can edit matches, so a copy someone changed is left alone.
//
// Survivors are chosen by `precedesAsCanonical`, so every device keeps the
// same row. The seeder and zone repair now wait for the first download
// (`FirstDownloadGate`), which stops new template copies at the source; the
// EventKit mirror still runs at launch, so these passes keep folding its
// rows on every dedup pass.

nonisolated extension DataCleanupService {

    /// Folds reminders mirroring one EventKit reminder onto one row, keeping
    /// every note attached to any of them.
    static func mergeSameEventKitReminders(
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer?
    ) -> Int {
        let key: (CDReminder) -> String? = { $0.eventKitReminderID }
        let prekey: ([String: Any]) -> String? = { $0["eventKitReminderID"] as? String }
        guard hasCollisions(CDReminder.self, columns: ["eventKitReminderID"], key: prekey, in: context) else {
            return 0
        }
        let fetch = CDFetchRequest(CDReminder.self)
        fetch.predicate = NSPredicate(format: "eventKitReminderID != nil")
        return fold(context.safeFetch(fetch), by: key, container: container, in: context) { canonical, duplicate in
            mergeReminder(canonical: canonical, duplicate: duplicate)
            if isFresher(duplicate.lastSyncedAt, than: canonical.lastSyncedAt) {
                canonical.title = duplicate.title
                canonical.notes = duplicate.notes
                canonical.dueDate = duplicate.dueDate
                canonical.isCompleted = duplicate.isCompleted
                canonical.completedAt = duplicate.completedAt
                canonical.updatedAt = duplicate.updatedAt
                canonical.eventKitCalendarID = duplicate.eventKitCalendarID
                canonical.lastSyncedAt = duplicate.lastSyncedAt
            }
        }
    }

    /// Folds calendar events mirroring the same occurrence of one EventKit
    /// event — same identifier, same start to the millisecond.
    static func mergeSameEventKitEvents(
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer?
    ) -> Int {
        let key: (CDCalendarEvent) -> String? = { occurrenceKey($0.eventKitEventID, $0.startDate) }
        let prekey: ([String: Any]) -> String? = {
            occurrenceKey($0["eventKitEventID"] as? String, $0["startDate"] as? Date)
        }
        let columns = ["eventKitEventID", "startDate"]
        guard hasCollisions(CDCalendarEvent.self, columns: columns, key: prekey, in: context) else { return 0 }
        let fetch = CDFetchRequest(CDCalendarEvent.self)
        fetch.predicate = NSPredicate(format: "eventKitEventID != nil")
        return fold(context.safeFetch(fetch), by: key, container: container, in: context) { canonical, duplicate in
            guard isFresher(duplicate.lastSyncedAt, than: canonical.lastSyncedAt) else { return }
            canonical.title = duplicate.title
            canonical.endDate = duplicate.endDate
            canonical.location = duplicate.location
            canonical.notes = duplicate.notes
            canonical.isAllDay = duplicate.isAllDay
            canonical.eventKitCalendarID = duplicate.eventKitCalendarID
            canonical.lastSyncedAt = duplicate.lastSyncedAt
        }
    }

    /// Folds note templates identical in title, text, category and tags.
    static func mergeIdenticalNoteTemplates(
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer?
    ) -> Int {
        // Tags are transformable, so the column pre-check leaves them out; the
        // object pass puts them back in the key.
        let prekey: ([String: Any]) -> String? = {
            contentKey([$0["title"] as? String, $0["body"] as? String, $0["categoryRaw"] as? String])
        }
        let columns = ["title", "body", "categoryRaw"]
        guard hasCollisions(CDNoteTemplate.self, columns: columns, key: prekey, in: context) else { return 0 }
        let key: (CDNoteTemplate) -> String? = {
            contentKey([$0.title, $0.body, $0.categoryRaw, $0.tagsArray.sorted().joined(separator: "\u{1E}")])
        }
        let rows = context.safeFetch(CDFetchRequest(CDNoteTemplate.self))
        return fold(rows, by: key, container: container, in: context) { canonical, duplicate in
            canonical.isBuiltIn = canonical.isBuiltIn || duplicate.isBuiltIn
            canonical.sortOrder = min(canonical.sortOrder, duplicate.sortOrder)
        }
    }

    /// Folds meeting templates identical in name and every prompt. The
    /// survivor stays the active template if any copy was.
    static func mergeIdenticalMeetingTemplates(
        using context: NSManagedObjectContext,
        container: NSPersistentCloudKitContainer?
    ) -> Int {
        let columns = ["name", "reflectionPrompt", "focusPrompt", "requestsPrompt", "guideNotesPrompt"]
        let prekey: ([String: Any]) -> String? = { row in contentKey(columns.map { row[$0] as? String }) }
        guard hasCollisions(CDMeetingTemplate.self, columns: columns, key: prekey, in: context) else { return 0 }
        let key: (CDMeetingTemplate) -> String? = {
            contentKey([$0.name, $0.reflectionPrompt, $0.focusPrompt, $0.requestsPrompt, $0.guideNotesPrompt])
        }
        let rows = context.safeFetch(CDFetchRequest(CDMeetingTemplate.self))
        return fold(rows, by: key, container: container, in: context) { canonical, duplicate in
            canonical.isActive = canonical.isActive || duplicate.isActive
            canonical.isBuiltIn = canonical.isBuiltIn || duplicate.isBuiltIn
            canonical.sortOrder = min(canonical.sortOrder, duplicate.sortOrder)
        }
    }

    // MARK: - Helpers

    /// Groups `rows` by `key` (rows without one are never merged), keeps the
    /// canonical row of each group, merges the rest into it and deletes them.
    private static func fold<T: NSManagedObject>(
        _ rows: [T],
        by key: (T) -> String?,
        container: NSPersistentCloudKitContainer?,
        in context: NSManagedObjectContext,
        merge: (T, T) -> Void
    ) -> Int {
        var groups: [String: [T]] = [:]
        for row in rows {
            guard let rowKey = key(row) else { continue }
            groups[rowKey, default: []].append(row)
        }
        var deleted = 0
        for (_, group) in groups where group.count > 1 {
            // No copy in iCloud yet: no record name to agree on (DedupSyncState).
            if DedupSyncState.noCopySent(group, container: container) { continue }
            let ordered = group.sorted { precedesAsCanonical($0, $1, container: container) }
            guard let canonical = ordered.first else { continue }
            for duplicate in ordered.dropFirst() {
                merge(canonical, duplicate)
                context.delete(duplicate)
                deleted += 1
            }
        }
        guard deleted > 0 else { return 0 }
        return saveFolds(in: context) ? deleted : 0
    }

    /// Whether two rows of `type` share a key, read from `columns` alone so a
    /// table without collisions — the usual answer — is never materialized.
    /// Answers true when it can't tell (unsaved changes, a failed fetch), so
    /// the caller falls back to the object pass.
    private static func hasCollisions<T: NSManagedObject>(
        _ type: T.Type,
        columns: [String],
        key: ([String: Any]) -> String?,
        in context: NSManagedObjectContext
    ) -> Bool {
        guard !context.hasChanges, let entityName = CDFetchRequest(type).entityName else { return true }
        let request = NSFetchRequest<NSDictionary>(entityName: entityName)
        request.resultType = .dictionaryResultType
        request.propertiesToFetch = columns
        guard let rows = try? context.fetch(request) else { return true }
        var seen = Set<String>(minimumCapacity: rows.count)
        for row in rows {
            guard let values = row as? [String: Any], let rowKey = key(values) else { continue }
            if !seen.insert(rowKey).inserted { return true }
        }
        return false
    }

    /// One occurrence of an EventKit event: its identifier and its start to
    /// the millisecond (CloudKit keeps dates in milliseconds; see
    /// `EventKitMirror.isSameInstant`).
    private static func occurrenceKey(_ eventID: String?, _ start: Date?) -> String? {
        guard let eventID else { return nil }
        let millis = start.map { String(Int64(($0.timeIntervalSince1970 * 1000).rounded())) } ?? "-"
        return eventID + "\u{1F}" + millis
    }

    /// The fields that make two templates the same, joined; a missing field
    /// reads as empty, which is what an unset template field holds.
    private static func contentKey(_ fields: [String?]) -> String? {
        fields.map { $0 ?? "" }.joined(separator: "\u{1F}")
    }

    private static func isFresher(_ lhs: Date?, than rhs: Date?) -> Bool {
        (lhs ?? .distantPast) > (rhs ?? .distantPast)
    }
}
