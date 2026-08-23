// Navigation state for one Albums surface — the Albums section in the main
// window, or a stand-alone album window. Each surface owns its own instance so
// opening a lesson in a second window doesn't move the main window's selection.

import SwiftUI

@Observable @MainActor
final class AlbumsNavModel {
    var selection: AlbumsSidebarItem? = .library
    var pageTarget: AlbumPageTarget?
    var showFolderPicker = false
    /// True in a stand-alone album window, where sidebar navigation
    /// doesn't exist and cross-album jumps must open a new window.
    var isAlbumWindow = false

    func jump(albumID: String, pageIndex: Int, highlight: String? = nil) {
        pageTarget = AlbumPageTarget(id: UUID(), albumID: albumID,
                                     pageIndex: pageIndex, highlight: highlight)
        selection = .album(albumID)
    }
}
