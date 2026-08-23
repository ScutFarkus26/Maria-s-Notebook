// AlbumWindowHost.swift
// Host view for reading one album in a separate macOS window — drag it to a
// second display, keep a lesson open while searching in the main window.

import SwiftUI

#if os(macOS)
struct AlbumWindowHost: View {
    /// Either an album id, or "albumID#page" to open at a specific page.
    let albumID: String?

    @Environment(AlbumLibrary.self) private var library
    @State private var nav: AlbumsNavModel = {
        let model = AlbumsNavModel()
        model.isAlbumWindow = true
        return model
    }()
    @State private var intelligence = AlbumIntelligence()

    private var parsed: (id: String, page: Int?)? {
        guard let albumID else { return nil }
        guard let hash = albumID.lastIndex(of: "#"),
              let page = Int(albumID[albumID.index(after: hash)...]) else {
            return (albumID, nil)
        }
        return (String(albumID[..<hash]), page)
    }

    var body: some View {
        core.focusedSceneValue(\.albumsNav, nav)
    }

    private var core: some View {
        Group {
            if let parsed, let album = library.album(id: parsed.id), library.state == .ready {
                AlbumDetailView(album: album)
                    .id(album.id)
                    .navigationTitle(album.title)
                    .onAppear {
                        if let page = parsed.page {
                            nav.pageTarget = AlbumPageTarget(id: UUID(), albumID: album.id,
                                                             pageIndex: page - 1, highlight: nil)
                        }
                    }
            } else if library.state == .loading || library.state == .needsFolder {
                ProgressView()
                    .task { library.bootstrapIfNeeded() }
            } else {
                ContentUnavailableView("Album not found", systemImage: "questionmark.folder")
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .environment(nav)
        .environment(intelligence)
    }
}
#endif
