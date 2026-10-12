// AlbumWindowHost.swift
// Host view for reading one album in a separate macOS window — drag it to a
// second display, keep a lesson open while searching in the main window.

import SwiftUI

#if os(macOS)
struct AlbumWindowHost: View {
    /// Either an album id, or "albumID#page" to open at a specific page.
    let albumID: String?

    @Environment(AlbumLibrary.self) private var library
    @Environment(\.managedObjectContext) private var context
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
            } else if library.state == .loading || (library.state == .needsFolder && !library.didBootstrap) {
                ProgressView()
            } else if library.state == .needsFolder {
                // Loaded, and this device has no album folder to read from.
                ContentUnavailableView(
                    "No Albums Folder", systemImage: "folder.badge.questionmark",
                    description: Text("Choose the folder that holds your album PDFs in Albums, "
                                      + "in the main window, then open the album again.")
                )
            } else {
                ContentUnavailableView("Album not found", systemImage: "questionmark.folder")
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .environment(nav)
        .environment(intelligence)
        .task {
            library.bootstrapIfNeeded()
            library.repairAlbumIdentities(in: context)
        }
        // A renamed or moved PDF keeps its annotations here too, as in the
        // Albums section (each load sets the flag).
        .onChange(of: library.state) { library.repairAlbumIdentities(in: context) }
        .onChange(of: library.needsIdentityRepair) { library.repairAlbumIdentities(in: context) }
    }
}
#endif
