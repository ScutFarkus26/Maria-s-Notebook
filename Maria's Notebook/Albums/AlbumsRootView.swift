// The Albums section: its own split view over the album library, shown by
// RootDetailContent when the guide picks Albums in the sidebar. The library
// loads lazily here rather than at app launch — opening every album PDF and
// indexing its text is too heavy for startup.

import SwiftUI
import UniformTypeIdentifiers

struct AlbumsRootView: View {
    @Environment(AlbumLibrary.self) private var library
    @Environment(\.appRouter) private var appRouter
    @Environment(\.managedObjectContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var nav = AlbumsNavModel()
    @State private var intelligence = AlbumIntelligence()
    @SceneStorage(UserDefaultsKeys.albumsSidebarSelection) private var storedSelection = ""

    var body: some View {
        #if os(macOS)
        core.focusedSceneValue(\.albumsNav, nav)
        #else
        core
        #endif
    }

    private var core: some View {
        @Bindable var nav = nav
        return Group {
            switch library.state {
            case .needsFolder, .failed:
                AlbumsWelcomeView()
            case .loading:
                ProgressView("Opening albums…")
                    .controlSize(.large)
            case .ready:
                NavigationSplitView {
                    AlbumsSidebar(selection: $nav.selection)
                } detail: {
                    detail
                }
            }
        }
        .environment(nav)
        .environment(intelligence)
        .fileImporter(isPresented: $nav.showFolderPicker,
                      allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                library.chooseFolder(url)
            }
        }
        .task {
            library.bootstrapIfNeeded()
            // The library may already be loaded from an earlier visit, in
            // which case no state change will arrive to trigger these.
            library.repairAlbumIdentities(in: context)
            consumeRouterRequest()
        }
        .onChange(of: library.state) {
            // A renamed or moved PDF keeps the guide's bookmarks, notes,
            // highlights, and ink instead of orphaning them.
            library.repairAlbumIdentities(in: context)
            consumeRouterRequest()
        }
        .onChange(of: appRouter.albumPageRequest) { consumeRouterRequest() }
        .onAppear {
            if let restored = AlbumsSidebarItem(rawStorage: storedSelection) {
                nav.selection = restored
            }
        }
        .onChange(of: nav.selection) {
            storedSelection = nav.selection?.rawStorage ?? ""
        }
        .onChange(of: scenePhase) {
            // Albums edited outside the app get picked up when the guide
            // comes back.
            if scenePhase == .active {
                library.refreshIfChanged()
            }
        }
    }

    /// Honours an "Open in Album" jump from a linked lesson. The request is
    /// held until the library is ready, since it usually arrives before the
    /// guide has ever opened this section and the PDFs are still loading.
    private func consumeRouterRequest() {
        guard library.state == .ready, let request = appRouter.albumPageRequest else { return }
        _ = appRouter.consumeAlbumPageRequest()
        nav.jump(albumID: request.albumID, pageIndex: request.pageIndex,
                 highlight: request.highlight)
    }

    @ViewBuilder
    private var detail: some View {
        switch nav.selection {
        case .library, nil:
            AlbumsLibraryView()
        case .search:
            AlbumsSearchView()
        case .ask:
            AlbumsAskView()
        case .bookmarks:
            AlbumBookmarksView()
        case .notes:
            AlbumNotesView()
        case .highlights:
            AlbumHighlightsView()
        case .album(let id):
            albumDetail(id: id)
        }
    }

    @ViewBuilder
    private func albumDetail(id: String) -> some View {
        if let album = library.album(id: id) {
            AlbumDetailView(album: album)
                .id(album.id)
        } else {
            ContentUnavailableView("Album not found", systemImage: "questionmark.folder")
        }
    }
}

// MARK: - Welcome / folder picking

struct AlbumsWelcomeView: View {
    @Environment(AlbumLibrary.self) private var library
    @State private var showPicker = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text("Your Albums, Searchable")
                .font(.largeTitle.bold())
            Text("""
                Choose the folder that holds your album PDFs.
                Every page becomes instantly searchable, with the table of contents, \
                bookmarks, and notes built in.
                """)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            if case .failed(let message) = library.state {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            Button {
                showPicker = true
            } label: {
                Label("Choose Albums Folder…", systemImage: "folder.badge.plus")
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(40)
        .frame(maxWidth: 560)
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                library.chooseFolder(url)
            }
        }
    }
}
