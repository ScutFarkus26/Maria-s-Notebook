import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

/// The shared shape of a PDF library screen (book club packets, stories): a header,
/// an adaptive card grid with a single-selection detail column, PDF import by
/// drag-and-drop or file importer behind one "Couldn't import PDF" alert, and an
/// empty state. The screens inject only what differs: header, card, detail, empty
/// state, drop prompt, logger and import service.
struct PDFLibraryListView<Item: NSManagedObject, Header: View, Card: View, Detail: View, EmptyState: View>: View {
    /// Every item, filtered or not; the selection is looked up here so a filter
    /// change doesn't dismiss the open detail column.
    let items: [Item]
    /// The items the grid shows.
    let filteredItems: [Item]
    @Binding var isShowingFileImporter: Bool
    /// Caption on the drag-and-drop overlay ("Drop PDF to add a story").
    let dropPrompt: String
    let logger: Logger
    /// Imports one PDF; returns the message to show when it fails, `nil` on success.
    let importPDF: (URL) -> String?
    @ViewBuilder let header: () -> Header
    @ViewBuilder let card: (Item, Bool) -> Card
    /// Builds the detail column for the selected item; call the closure to close it.
    @ViewBuilder let detail: (Item, @escaping () -> Void) -> Detail
    @ViewBuilder let emptyState: () -> EmptyState

    @State private var selectedID: NSManagedObjectID?
    @State private var isDropTargeted = false
    @State private var importErrorMessage: String?

    private var selectedItem: Item? {
        guard let id = selectedID else { return nil }
        return items.first { $0.objectID == id }
    }

    var body: some View {
        HStack(spacing: 0) {
            mainColumn
            if let item = selectedItem {
                Divider()
                detail(item) { selectedID = nil }
                    .frame(width: 480)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedID)
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
            header()
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

    @ViewBuilder
    private var content: some View {
        if filteredItems.isEmpty {
            emptyState()
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 320), spacing: 16)], spacing: 16) {
                ForEach(filteredItems, id: \.objectID) { item in
                    cardButton(for: item)
                }
            }
            .padding(16)
        }
    }

    private func cardButton(for item: Item) -> some View {
        let isSelected = item.objectID == selectedID
        return Button {
                selectedID = isSelected ? nil : item.objectID
            } label: {
                card(item, isSelected)
            }
            .buttonStyle(.plain)
            .accessibilityValue(isSelected ? "Selected" : "Not selected")
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
                    Text(dropPrompt)
                        .font(.headline)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .allowsHitTesting(false)
        }
    }

    // MARK: - Drop / Import

    private func handleDrop(providers: [NSItemProvider]) {
        let logger = self.logger
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, error in
                guard let url else {
                    if let error {
                        logger.warning("Drop failed: \(error.localizedDescription, privacy: .public)")
                    }
                    return
                }
                // The provided URL is in a temp location that gets cleaned up when the
                // closure returns; copy to a stable temp path before hopping main actor.
                let tempCopy = PDFDropSupport.copyToTempIfNeeded(url, logger: logger)
                Task { @MainActor in
                    performImport(at: tempCopy ?? url)
                }
            }
        }
    }

    private func handleFileImporter(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                let didStart = url.startAccessingSecurityScopedResource()
                defer { if didStart { url.stopAccessingSecurityScopedResource() } }
                performImport(at: url)
            }
        case .failure(let error):
            importErrorMessage = error.localizedDescription
        }
    }

    private func performImport(at url: URL) {
        if let message = importPDF(url) {
            importErrorMessage = message
        }
    }
}

/// Off-main-actor support for dropped PDFs. Kept outside the generic view so the
/// `@Sendable` load-completion closure captures no generic metatypes.
private enum PDFDropSupport {
    nonisolated static func copyToTempIfNeeded(_ url: URL, logger: Logger) -> URL? {
        let fm = FileManager.default
        let temp = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        do {
            try fm.copyItem(at: url, to: temp)
            return temp
        } catch {
            logger.warning("Failed to copy dropped PDF to temp: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

/// The empty state of a `PDFLibraryListView`: one message when the library has
/// nothing at all, another (with a "Clear filters" button) when the filters hide
/// everything. `footer` renders under the hint only while the library is empty.
struct PDFLibraryEmptyState<Footer: View>: View {
    let systemImage: String
    let isLibraryEmpty: Bool
    let emptyTitle: String
    let filteredTitle: String
    let hint: String
    let clearFilters: () -> Void
    @ViewBuilder let footer: () -> Footer

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.secondary)
            Text(isLibraryEmpty ? emptyTitle : filteredTitle)
                .font(.title3.weight(.semibold))
            if isLibraryEmpty {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                footer()
            } else {
                Button("Clear filters", action: clearFilters)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
