// AppRouter+Handoff.swift
// Where a Handoff from another device lands.

import Foundation

extension AppRouter {
    /// Opens what another device handed off (see `Handoff`), the way the app's
    /// own jumps open it: a student in its own window on the Mac and in the
    /// Students tab elsewhere, a lesson in the Lessons section, an album page
    /// in the reader.
    func continueHandoff(to destination: Handoff.Destination) {
        switch destination {
        case .student(let id):
            requestOpenStudentDetail(id)
        case .lesson(let id):
            navigateToLesson(id)
        case .albumPage(let albumID, let pageIndex):
            navigateToAlbumPage(albumID: albumID, pageIndex: pageIndex)
        }
    }

    /// As `continueHandoff(to:)`, for the main window that took the activity
    /// once its screen is up (`WindowHandoff`): that window switches section
    /// itself (`select`), rather than every main window racing for the
    /// router's section request (review c #3). What to open inside the section
    /// still waits here, for that section to take on appear.
    func continueHandoff(to destination: Handoff.Destination, selectingIn select: (RootView.NavigationItem) -> Void) {
        switch destination {
        case .student(let id):
            #if os(macOS)
            openStudentInNewWindow(id)
            #else
            navigationDestination = .openStudentDetail(id)
            select(.students)
            #endif
        case .lesson(let id):
            pendingLessonID = id
            select(.lessons)
        case .albumPage(let albumID, let pageIndex):
            albumPageRequest = AlbumPageRequest(albumID: albumID, pageIndex: pageIndex)
            select(.teachingAlbums)
        }
    }
}
