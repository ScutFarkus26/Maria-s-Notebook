//
//  WindowCreateRequests.swift
//  Cosmic Daybook
//
//  New Lesson, New Student and Import Students asked for in one main window.
//

import SwiftUI

/// One main window's pending New Lesson / New Student / Import Students
/// request, for that window's Lessons or Students screen to answer.
///
/// RootView makes one per window and passes it down by environment. File ›
/// New Lesson… and the sidebar's menus go through the window's
/// `QuickCaptureActions`, which land here; they used to set the shared
/// `AppRouter`, which every window's Lessons and Students observe, so with
/// two windows the sheet could open in the window behind the key one.
/// `AppRouter.requestNewLesson` stays for callers with no window (Siri,
/// a request made while the app is still opening).
@Observable
final class WindowCreateRequests {
    enum Request: Equatable {
        case newLesson(defaultArea: String?, defaultSequence: String?)
        case newStudent
        case importStudents

        /// The section that shows the request's sheet.
        var answeringSection: RootView.NavigationItem {
            switch self {
            case .newLesson: .lessons
            case .newStudent, .importStudents: .students
            }
        }
    }

    private(set) var pending: Request?

    func ask(_ request: Request) {
        pending = request
    }

    /// Takes a pending New Lesson request, leaving a Students one in place.
    func consumeNewLesson() -> AppRouter.NewLessonRequest? {
        guard case .newLesson(let area, let sequence) = pending else { return nil }
        pending = nil
        return AppRouter.NewLessonRequest(defaultArea: area, defaultSequence: sequence)
    }

    /// Takes a pending New Student or Import Students request, leaving a New
    /// Lesson one in place.
    func consumeStudentRequest() -> Request? {
        guard let request = pending, request.answeringSection == .students else { return nil }
        pending = nil
        return request
    }
}

extension EnvironmentValues {
    /// The enclosing main window's create requests. Nil outside a main window
    /// (a detail window, a preview), where only the router's requests apply.
    @Entry var windowCreateRequests: WindowCreateRequests?
}
