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
        let request = NSFetchRequest<CDStudentFocusItem>(entityName: "StudentFocusItem")
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
        let request = NSFetchRequest<CDStudentFocusItem>(entityName: "StudentFocusItem")
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

    /// Reorders focus items by updating their sortOrder values.
    static func reorder(_ items: [CDStudentFocusItem]) {
        for (index, item) in items.enumerated() {
            item.sortOrder = Int64(index)
        }
    }
}
