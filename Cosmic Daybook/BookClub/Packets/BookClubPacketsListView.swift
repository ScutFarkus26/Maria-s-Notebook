import SwiftUI
import CoreData

struct BookClubPacketsListView: View {
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
            filteredItems: viewModel.filter(packets: allPackets),
            isShowingFileImporter: $isShowingFileImporter,
            dropPrompt: "Drop PDF to add a packet",
            logger: .bookClub,
            importPDF: { importPDF(at: $0) },
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
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search packets", text: $viewModel.searchText)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .surface(UIConstants.CornerRadius.medium, fill: Color.secondary.opacity(0.1), style: .continuous)

            Spacer()

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
            hint: "Drag a PDF here, or use Add Packet, to import a book club packet.",
            clearFilters: { viewModel.clearAll() },
            footer: { EmptyView() }
        )
    }

    /// Returns the alert message when the import fails, `nil` on success.
    private func importPDF(at url: URL) -> String? {
        do {
            try BookClubImportService.importPDF(at: url, context: viewContext)
            return nil
        } catch let error as BookClubImportService.ImportRejection {
            return error.errorDescription
        } catch {
            return error.localizedDescription
        }
    }
}
