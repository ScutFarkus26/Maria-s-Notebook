import SwiftUI

// MARK: - Sheet Types & Content

extension AlbumDetailView {

    /// The one sheet the album reader can show at a time. The Go to Page
    /// alert, the PDF exporter, and the toolbar popovers stay on their own
    /// state: they are different kinds of presentation, and each popover is
    /// anchored to its own toolbar item.
    enum ActiveSheet: Identifiable {
        case summary(AlbumSummaryState)
        #if os(iOS)
        case outline
        #endif

        var id: String {
            switch self {
            case .summary(let state): return "summary_\(state.id.uuidString)"
            #if os(iOS)
            case .outline: return "outline"
            #endif
            }
        }
    }

    @ViewBuilder
    func sheetContent(for sheet: ActiveSheet) -> some View {
        switch sheet {
        case .summary(let state):
            AlbumSummarySheet(state: state, album: album) { text, lesson in
                AlbumUserDataStore.addNote(albumID: album.id, pageIndex: lesson.pageIndex,
                                 lessonTitle: lesson.title, text: text, in: context)
            }
        #if os(iOS)
        case .outline:
            NavigationStack {
                AlbumOutlineListView(album: album, currentPage: currentPage) { node in
                    activeSheet = nil
                    goTo(pageIndex: node.pageIndex)
                }
                .navigationTitle("Contents")
                .navigationBarTitleDisplayMode(.inline)
            }
        #endif
        }
    }
}
