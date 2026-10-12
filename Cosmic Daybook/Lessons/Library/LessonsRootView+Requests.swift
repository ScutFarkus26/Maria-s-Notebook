// LessonsRootView+Requests.swift
// Lessons asked for from elsewhere: a lesson to reveal, and New Lesson (this
// window's own request first, else the router's).

import SwiftUI

extension LessonsRootView {
    /// Reveals a lesson requested from elsewhere in the app — today, the
    /// album reader's "Notebook Lesson" jump on a linked album page.
    func openPendingLesson() {
        guard let id = appRouter.pendingLessonID else { return }
        _ = appRouter.consumePendingLessonID()
        guard let lesson = lessons.first(where: { $0.id == id }) else { return }
        // Clear any area filter that would hide the lesson from its column.
        if !lesson.area.trimmed().isEmpty, filterState.selectedArea != lesson.area {
            filterState.selectedArea = lesson.area
        }
        selectedLessonDetail = lesson
    }

    /// Opens the New Lesson sheet asked for in this window (File › New
    /// Lesson…, the sidebar) or, with no window to ask, through the router
    /// (Siri, a request made while the app was opening). Either one also
    /// brought this section up.
    func openNewLessonRequest() {
        guard let request = windowCreateRequests?.consumeNewLesson() ?? appRouter.consumeNewLessonRequest()
        else { return }
        addLessonContext = AddLessonContext(
            source: nil, defaultArea: request.defaultArea, defaultSequence: request.defaultSequence
        )
    }
}
