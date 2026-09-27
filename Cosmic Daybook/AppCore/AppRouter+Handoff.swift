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
            #if !os(macOS)
            selectedNavItem = .students
            #endif
            requestOpenStudentDetail(id)
        case .lesson(let id):
            navigateToLesson(id)
        case .albumPage(let albumID, let pageIndex):
            navigateToAlbumPage(albumID: albumID, pageIndex: pageIndex)
        }
    }
}
