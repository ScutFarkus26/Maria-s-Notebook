import SwiftUI
import CoreData

/// Resources › Packets: book club packet PDFs with their reading items. A
/// packet's detail starts a book club, which then lives in Clubs & Projects.
struct PacketsLibrary: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDBookClubPacket.createdAt, ascending: false)],
        animation: .default
    )
    private var packets: FetchedResults<CDBookClubPacket>

    @State private var viewModel = BookClubPacketsViewModel()
    @State private var isShowingFileImporter = false

    var body: some View {
        let allPackets = Array(packets)
        PDFLibraryListView(
            items: allPackets,
            sections: [PDFLibrarySection(title: nil, items: viewModel.filter(packets: allPackets))],
            isShowingFileImporter: $isShowingFileImporter,
            dropPrompt: "Drop PDF to add a packet",
            logger: .bookClub,
            importPDF: { url in
                do {
                    try LibraryImportService.importPacket(at: url, context: viewContext)
                    return nil
                } catch {
                    return LibraryImportService.message(for: error)
                }
            },
            header: { headerBar },
            card: { packet, isSelected in
                BookClubPacketCardView(packet: packet, isSelected: isSelected)
            },
            detail: { packet, dismiss in
                BookClubPacketDetailView(packet: packet, onClose: dismiss, onDelete: dismiss)
            },
            emptyState: { emptyState }
        )
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            LibrarySearchField(prompt: "Search packets", text: $viewModel.searchText)
            Spacer(minLength: 0)
            Button {
                isShowingFileImporter = true
            } label: {
                Label("Add Packet", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var emptyState: some View {
        PDFLibraryEmptyState(
            systemImage: "books.vertical.circle",
            isLibraryEmpty: packets.isEmpty,
            emptyTitle: "No book club packets yet",
            filteredTitle: "No packets match your filters",
            hint: PlatformIdiom.isPhone
                ? "Use Add Packet to import a book club packet."
                : "Drag a PDF here, or use Add Packet, to import a book club packet.",
            clearFilters: { viewModel.clearAll() },
            footer: { EmptyView() }
        )
    }
}
