import SwiftUI
import CoreData

// What the Classroom sheet reads from the store, once when it opens and
// again after each change (`AssistantClassroomSheet.followStore`), and the
// note the tabs follow to hold their name sheet back while it's up. Setup's
// last pages read the guide's settings the same way.

extension AssistantClassroomSheet {

    var displayName: String? {
        guard let name = storedName?.trimmed(), !name.isEmpty else { return nil }
        return name
    }

    /// Reads the settings and membership from `context` now, and again
    /// after each change in the store, while the sheet is up: they were
    /// fetched six to eight times on every redraw, and the reminder picker
    /// and the switches redraw it often (hunt 2026-11-03 #8).
    func followStore(in context: NSManagedObjectContext?) async {
        readFacts = AssistantClassroomFacts(in: context)
        let changes = NotificationCenter.default.notifications(named: .NSPersistentStoreRemoteChange).map { _ in () }
        for await _ in changes {
            let read = AssistantClassroomFacts(in: context)
            if read != readFacts { readFacts = read }
        }
    }
}

extension Notification.Name {
    /// The Classroom sheet came up (`object` true) or went (false).
    static let assistantClassroomSheet = Notification.Name("Assistant.classroomSheet")
}

/// The guide's attendance settings as Classroom and setup show them, from
/// one fetch: the due time ("9:00 AM") once the guide has set up the
/// front-desk email or picked ParentLocker in the notebook, and whether
/// ParentLocker is the way attendance goes.
struct AssistantAttendanceSending: Equatable {
    var dueAt: String?
    var sendsToParentLocker = false

    init(in context: NSManagedObjectContext?) {
        guard let context, let settings = AttendanceEmailLog.settings(in: context) else { return }
        if settings.canSendAttendance { dueAt = FrontDeskEmailReminder.timeString(settings.deadlineMinutes) }
        sendsToParentLocker = settings.sendMethod == .parentLocker
    }
}

/// What the Classroom sheet shows from the store: the guide's settings,
/// when she joined, and the pinned share zone's short ID ("DB5879EF").
struct AssistantClassroomFacts: Equatable {
    var sending: AssistantAttendanceSending
    var joined: Date?
    var classroomID: String?

    init(in context: NSManagedObjectContext?) {
        sending = AssistantAttendanceSending(in: context)
        guard let context else { return }
        joined = CDClassroomMembership.current(in: context)?.joinedAt
        classroomID = CDClassroomMembership.pinnedZoneName(in: context)
            .map(CDClassroomMembership.classroomID(forZone:))
    }
}
