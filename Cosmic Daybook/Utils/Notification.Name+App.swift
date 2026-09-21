import Foundation

// App-wide notification names that belong to no single service: the requests to
// open a detached window, and the "a note was saved" ping the note-reading
// screens refresh on. Service-owned names (classroom sharing, the school
// calendar, memory pressure, synced preferences) stay with their service.
extension Notification.Name {
    /// Posted to request opening a student detail window (with UUID userInfo)
    nonisolated static let openStudentDetailWindow = Notification.Name("openStudentDetailWindow")
    /// Posted to request opening a lesson detail window (with UUID userInfo)
    nonisolated static let openLessonDetailWindow = Notification.Name("openLessonDetailWindow")
    /// Posted to request opening a work detail window (with UUID userInfo)
    nonisolated static let openWorkDetailWindow = Notification.Name("openWorkDetailWindow")
    /// Posted to request opening the keyboard shortcuts help window
    nonisolated static let openKeyboardShortcutsWindow = Notification.Name("openKeyboardShortcutsWindow")
    /// Posted after a note is saved, with the note's id as the object
    nonisolated static let noteDidSave = Notification.Name("CosmicDaybook.noteDidSave")
}
