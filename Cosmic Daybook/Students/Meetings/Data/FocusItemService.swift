import Foundation
import CoreData
import OSLog

/// Service for managing student focus items that carry forward between meetings.
enum FocusItemService {
    private static let logger = Logger.students

    /// Fetches all active focus items for a student, sorted by sortOrder.
    static func fetchActive(
        studentID: UUID,
        context: NSManagedObjectContext
    ) -> [CDStudentFocusItem] {
        let request = CDFetchRequest(CDStudentFocusItem.self)
        request.predicate = NSPredicate(
            format: "studentID == %@ AND statusRaw == %@",
            studentID.uuidString,
            FocusItemStatus.active.rawValue
        )
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    /// Creates a new focus item for a student, linked to the meeting that created it.
    @discardableResult
    static func create(
        studentID: UUID,
        text: String,
        meetingID: UUID,
        sortOrder: Int,
        context: NSManagedObjectContext
    ) -> CDStudentFocusItem {
        let item = CDStudentFocusItem(context: context)
        item.studentIDUUID = studentID
        item.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        item.createdInMeetingIDUUID = meetingID
        item.sortOrder = Int64(sortOrder)
        item.createdAt = Date()
        item.statusRaw = FocusItemStatus.active.rawValue
        return item
    }

    /// Resolves a focus item, recording which meeting resolved it.
    static func resolve(_ item: CDStudentFocusItem, inMeetingID meetingID: UUID) {
        item.status = .resolved
        item.resolvedInMeetingIDUUID = meetingID
        item.resolvedAt = Date()
        logger.debug("Focus item '\(item.text)' resolved in meeting \(meetingID)")
    }

    /// Resolves a focus item outside a meeting — from the Watching list or
    /// over MCP. No resolving meeting is recorded, only the time.
    static func resolve(_ item: CDStudentFocusItem) {
        item.status = .resolved
        item.resolvedInMeetingIDUUID = nil
        item.resolvedAt = Date()
        logger.debug("Focus item '\(item.text)' resolved outside a meeting")
    }

    /// Drops a focus item (no longer relevant), recording which meeting dropped it.
    static func drop(_ item: CDStudentFocusItem, inMeetingID meetingID: UUID) {
        item.status = .dropped
        item.resolvedInMeetingIDUUID = meetingID
        item.resolvedAt = Date()
        logger.debug("Focus item '\(item.text)' dropped in meeting \(meetingID)")
    }

    /// Fetches focus items that were created or resolved in a specific meeting.
    static func fetchForMeeting(
        meetingID: UUID,
        context: NSManagedObjectContext
    ) -> [CDStudentFocusItem] {
        let meetingIDString = meetingID.uuidString
        let request = CDFetchRequest(CDStudentFocusItem.self)
        request.predicate = NSPredicate(
            format: "createdInMeetingID == %@ OR resolvedInMeetingID == %@",
            meetingIDString,
            meetingIDString
        )
        request.sortDescriptors = [NSSortDescriptor(key: "sortOrder", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    /// Generates a plain-text summary of focus items for backward-compatible storage
    /// in CDStudentMeeting.focus.
    static func snapshotText(
        activeItems: [CDStudentFocusItem],
        resolvedItems: [CDStudentFocusItem],
        newTexts: [String]
    ) -> String {
        var lines: [String] = []

        for item in resolvedItems {
            lines.append("[done] \(item.text)")
        }

        for item in activeItems {
            lines.append("• \(item.text)")
        }

        for text in newTexts where !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("• \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - A meeting's checklist

    /// What a meeting changed on the focus checklist: items ticked off,
    /// items dropped and new ones typed. The Meetings workflow keeps them in
    /// its draft; Complete and the student record's Save to History both file
    /// them through here (bug hunt 2026-10-10, #10).
    struct ChecklistChanges {
        var resolvedIDs: Set<UUID> = []
        var droppedIDs: Set<UUID> = []
        var newTexts: [String] = []

        var isEmpty: Bool {
            resolvedIDs.isEmpty && droppedIDs.isEmpty && newTexts.allSatisfy { $0.trimmed().isEmpty }
        }

        /// The history entry's focus: the checklist as the meeting leaves it
        /// (`active` is the list it started from), then any focus typed on
        /// the student record's Meetings tab.
        func historyText(active: [CDStudentFocusItem], typed: String) -> String {
            let resolved = active.filter { $0.id.map(resolvedIDs.contains) ?? false }
            let carried = active.filter { item in
                guard let id = item.id else { return false }
                return !resolvedIDs.contains(id) && !droppedIDs.contains(id)
            }
            return [
                FocusItemService.snapshotText(activeItems: carried, resolvedItems: resolved, newTexts: newTexts),
                typed
            ].filter { !$0.isEmpty }.joined(separator: "\n")
        }

        /// Resolves and drops the ticked items and creates the new ones, all
        /// under `meetingID`. Nothing here saves.
        func file(
            active: [CDStudentFocusItem], studentID: UUID, meetingID: UUID, context: NSManagedObjectContext
        ) {
            for item in active {
                guard let itemID = item.id else { continue }
                if resolvedIDs.contains(itemID) {
                    FocusItemService.resolve(item, inMeetingID: meetingID)
                } else if droppedIDs.contains(itemID) {
                    FocusItemService.drop(item, inMeetingID: meetingID)
                }
            }
            for (index, text) in newTexts.enumerated() {
                let trimmed = text.trimmed()
                guard !trimmed.isEmpty else { continue }
                FocusItemService.create(
                    studentID: studentID, text: trimmed, meetingID: meetingID,
                    sortOrder: active.count + index, context: context
                )
            }
        }
    }
}
