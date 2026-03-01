#if os(macOS)
import SwiftUI

/// View modifier that listens for window-opening notifications and opens appropriate windows
struct OpenWindowOnNotificationModifier: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .openNewWindow)) { _ in
                openWindow(id: "mainWindow")
            }
            .onReceive(NotificationCenter.default.publisher(for: .openStudentDetailWindow)) { notification in
                if let studentID = notification.userInfo?["studentID"] as? UUID {
                    openWindow(id: "StudentDetailWindow", value: studentID)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openLessonDetailWindow)) { notification in
                if let lessonID = notification.userInfo?["lessonID"] as? UUID {
                    openWindow(id: "LessonDetailWindow", value: lessonID)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openWorkDetailWindow)) { notification in
                if let workID = notification.userInfo?["workID"] as? UUID {
                    openWindow(id: "WorkDetailWindow", value: workID)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .openKeyboardShortcutsWindow)) { _ in
                openWindow(id: "KeyboardShortcutsWindow")
            }
    }
}

// MARK: - Helper functions for posting window notifications

/// Opens a student detail in a new window
func openStudentInNewWindow(_ studentID: UUID) {
    NotificationCenter.default.post(
        name: .openStudentDetailWindow,
        object: nil,
        userInfo: ["studentID": studentID]
    )
}

/// Opens a lesson detail in a new window
func openLessonInNewWindow(_ lessonID: UUID) {
    NotificationCenter.default.post(
        name: .openLessonDetailWindow,
        object: nil,
        userInfo: ["lessonID": lessonID]
    )
}

/// Opens a work detail in a new window
func openWorkInNewWindow(_ workID: UUID) {
    NotificationCenter.default.post(
        name: .openWorkDetailWindow,
        object: nil,
        userInfo: ["workID": workID]
    )
}
#endif

