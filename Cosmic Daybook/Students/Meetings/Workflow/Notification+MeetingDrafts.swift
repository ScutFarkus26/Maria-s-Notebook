import Foundation

extension Notification.Name {
    /// A child's meeting draft appeared or went away (the queue's pencil).
    static let meetingDraftsDidChange = Notification.Name("MeetingsDraftsDidChange")
    /// A child's stored meeting draft changed in any way: written, cleared or
    /// filed. The child's ID is in the user info
    /// (`MeetingPersistenceService.studentID(of:)`).
    static let meetingDraftDidChange = Notification.Name("MeetingDraftDidChange")
}
