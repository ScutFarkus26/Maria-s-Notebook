// ShowInAlbumButton.swift
// "Show in Album" as a context-menu item: one jump from a lesson pill to the
// album page that lesson is written up on.
//
// The link is read off the lesson itself and the jump goes through
// `AppRouter.shared` rather than `@Environment`, for the reason
// `ShowInChecklistButton` gives: menu content is built outside the presenting
// view's own tree, so the environment it would read is not there.
//
// Stays in the menu, disabled, when the lesson has no link — a missing item
// reads as "this app can't do that", a greyed one as "this lesson isn't
// matched yet", and only the second is true. The card's Album row is where
// the guide links it.

import SwiftUI

struct ShowInAlbumButton: View {
    let lesson: CDLesson

    var body: some View {
        Button("Show in Album", systemImage: "books.vertical") {
            guard let link = lesson.albumLink else { return }
            AppRouter.shared.navigateToAlbumPage(albumID: link.albumID,
                                                 pageIndex: link.pageIndex)
        }
        .disabled(lesson.albumLink == nil)
    }
}
