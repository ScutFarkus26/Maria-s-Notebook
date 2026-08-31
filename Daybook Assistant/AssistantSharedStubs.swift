import Foundation

// Declarations the shared files reach for, whose real homes carry dependencies
// this app has no use for. Each is deliberately inert here.

extension Notification.Name {
    /// `CoreDataStack` posts this after a remote change touches the school
    /// calendar. In the notebook it lives on `SchoolCalendarService`, which
    /// brings the whole school-day model with it; nothing in this app listens,
    /// so the name is all that's needed.
    static let schoolDayDataDidChange = Notification.Name("schoolDayDataDidChange")
}
