import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

struct BookClubPacketsListView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \CDBookClubPacket.createdAt, ascending: false)],
        animation: .default
    )
    private var packets: FetchedResults<CDBookClubPacket>

    @State private var viewModel = BookClubPacketsViewModel()
    @State private var selectedPacketID: NSManagedObjectID?
    @State private var isShowingFileImporter = false
    @State private var isDropTargeted = false
    @State private var importErrorMessage: String?

    nonisolated private static let logger = Logger.bookClub

    private var filteredPackets: [CDBookClubPacket] {
        viewModel.filter(packets: Array(packets))
    }

    private var selectedPacket: CDBookClubPacket? {
        guard let id = selectedPacketID else { return nil }
        return packets.first { $0.objectID == id }
    }

    var body: some View {
        HStack(spacing: 0) {
            mainColumn
            if let packet = selectedPacket {
                Divider()
                BookClubPacketDetailView(
                    packet: packet,
                    onClose: { selectedPacketID = nil },
                    onDelete: { selectedPacketID = nil }
                )
                .frame(width: 480)
                .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedPacketID)
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [UTType.pdf],
            allowsMultipleSelection: true
        ) { result in
            handleFileImporter(result)
        }
        .alert(
            "Couldn't import PDF",
            isPresented: Binding(
                get: { importErrorMessage != nil },
                set: { if !$0 { importErrorMessage = nil } }
            ),
            presenting: importErrorMessage
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(dropOverlay)
        .onDrop(of: [UTType.pdf], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
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
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.1))
            )

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

    @ViewBuilder
    private var content: some View {
        if filteredPackets.isEmpty {
            emptyState
        } else {
            packetsGrid
        }
    }

    private var packetsGrid: some View {
        ScrollView {
            LazyVGrid(columns: gridColumns, spacing: 16) {
                ForEach(filteredPackets, id: \.objectID) { packet in
                    packetCard(for: packet)
                }
            }
            .padding(16)
        }
    }

    private var gridColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)]
    }

    private func packetCard(for packet: CDBookClubPacket) -> some View {
        let isSelected = packet.objectID == selectedPacketID
        return BookClubPacketCardView(packet: packet, isSelected: isSelected)
            .onTapGesture {
                selectedPacketID = isSelected ? nil : packet.objectID
            }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical.circle")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text(packets.isEmpty ? "No book club packets yet" : "No packets match your filters")
                .font(.title3.weight(.semibold))
            if packets.isEmpty {
                Text("Drag a PDF here, or use Add Packet, to import a book club packet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Button("Clear filters") { viewModel.clearAll() }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var dropOverlay: some View {
        if isDropTargeted {
            ZStack {
                Color.accentColor.opacity(0.08)
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                    Text("Drop PDF to add a packet")
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Drop / Import

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, error in
                guard let url else {
                    if let error {
                        Self.logger.warning("Drop failed: \(error.localizedDescription, privacy: .public)")
                    }
                    return
                }
                let tempCopy = Self.copyToTempIfNeeded(url)
                Task { @MainActor in
                    importPDF(at: tempCopy ?? url)
                }
            }
        }
    }

    nonisolated private static func copyToTempIfNeeded(_ url: URL) -> URL? {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        do {
            try fm.copyItem(at: url, to: temp)
            return temp
        } catch {
            Self.logger.warning("Failed to copy dropped PDF to temp: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func handleFileImporter(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }
                importPDF(at: url)
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }

    private func importPDF(at url: URL) {
        do {
            try BookClubImportService.importPDF(at: url, context: viewContext)
        } catch let error as BookClubImportService.ImportRejection {
            importErrorMessage = error.errorDescription
        } catch {
            importErrorMessage = error.localizedDescription
        }
    }
}
