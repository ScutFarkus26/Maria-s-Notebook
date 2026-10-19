import SwiftUI
import CoreData
import UniformTypeIdentifiers
import OSLog

/// The shape of every list on the Resources screen (stories, book club packets,
/// resource files, procedures): a header, an adaptive card grid in optional
/// sections, a detail column for the selected card (a sheet at compact width),
/// PDF import by drag-and-drop or file importer behind one "Couldn't Add the
/// PDF" alert, an optional select mode, and an empty state. The lists inject
/// only what differs: header, card, detail, empty state, drop prompt, logger
/// and import.
struct PDFLibraryListView<Item: NSManagedObject, Header: View, Card: View, Detail: View, EmptyState: View>: View {
    /// Every item, filtered or not; the selection is looked up here so a filter
    /// change doesn't dismiss the open detail column.
    let items: [Item]
    /// The items the grid shows, in the sections it shows them in.
    let sections: [PDFLibrarySection<Item>]
    @Binding var isShowingFileImporter: Bool
    /// Caption on the drag-and-drop overlay ("Drop PDF to add a story").
    let dropPrompt: String
    let logger: Logger
    /// Imports one PDF; returns the message to show when it fails, `nil` on
    /// success. Nil for a list that takes no PDFs (procedures): no drop target.
    let importPDF: ((URL) -> String?)?
    /// When set, the grid is in select mode: a tap ticks the card instead of
    /// opening it.
    let multiSelection: Binding<Set<NSManagedObjectID>>?
    @ViewBuilder let header: () -> Header
    @ViewBuilder let card: (Item, Bool) -> Card
    /// Builds the detail for the selected item; call the closure to close it.
    @ViewBuilder let detail: (Item, @escaping () -> Void) -> Detail
    @ViewBuilder let emptyState: () -> EmptyState

    @State private var selectedID: NSManagedObjectID?
    @State private var isDropTargeted = false
    @State private var importErrorMessage: String?

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    init(
        items: [Item],
        sections: [PDFLibrarySection<Item>],
        isShowingFileImporter: Binding<Bool> = .constant(false),
        dropPrompt: String = "",
        logger: Logger,
        importPDF: ((URL) -> String?)?,
        multiSelection: Binding<Set<NSManagedObjectID>>? = nil,
        @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder card: @escaping (Item, Bool) -> Card,
        @ViewBuilder detail: @escaping (Item, @escaping () -> Void) -> Detail,
        @ViewBuilder emptyState: @escaping () -> EmptyState
    ) {
        self.items = items
        self.sections = sections
        self._isShowingFileImporter = isShowingFileImporter
        self.dropPrompt = dropPrompt
        self.logger = logger
        self.importPDF = importPDF
        self.multiSelection = multiSelection
        self.header = header
        self.card = card
        self.detail = detail
        self.emptyState = emptyState
    }

    /// A phone has no room for a detail column beside the grid; it gets a sheet.
    private var showsDetailAsSheet: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    private var selectedItem: Item? {
        guard let id = selectedID else { return nil }
        return items.first { $0.objectID == id }
    }

    /// The open item as a sheet's item, at compact width.
    private var sheetItem: Binding<PDFLibrarySelectedObject?> {
        Binding(
            get: { showsDetailAsSheet ? selectedID.map(PDFLibrarySelectedObject.init) : nil },
            set: { if $0 == nil { selectedID = nil } }
        )
    }

    var body: some View {
        HStack(spacing: 0) {
            mainColumn
            if !showsDetailAsSheet, let item = selectedItem {
                Divider()
                // Keyed by the item, so picking another card starts the detail afresh
                // (its preview, download and viewed stamp are per item).
                detail(item) { selectedID = nil }
                    .id(item.objectID)
                    .frame(width: 480)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: selectedID)
        .sheet(item: sheetItem) { selected in
            if let item = items.first(where: { $0.objectID == selected.id }) {
                detail(item) { selectedID = nil }
                    .id(item.objectID)
            }
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [UTType.pdf],
            allowsMultipleSelection: true
        ) { result in
            handleFileImporter(result)
        }
        .alert(
            "Couldn't Add the PDF",
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
        .onChange(of: multiSelection != nil) { _, isSelecting in
            if isSelecting { selectedID = nil }
        }
    }

    private var mainColumn: some View {
        VStack(spacing: 0) {
            header()
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if isDropTargeted {
                PDFLibraryDropOverlay(prompt: dropPrompt)
            }
        }
        .onDrop(of: importPDF == nil ? [] : [UTType.pdf], isTargeted: $isDropTargeted) { providers in
            guard importPDF != nil else { return false }
            handleDrop(providers: providers)
            return true
        }
    }

    @ViewBuilder
    private var content: some View {
        if sections.allSatisfy(\.items.isEmpty) {
            emptyState()
        } else {
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(sections.filter { !$0.items.isEmpty }) { section in
                    if let title = section.title {
                        PDFLibrarySectionHeading(
                            title: title,
                            systemImage: section.systemImage,
                            subtitle: section.subtitle,
                            count: section.items.count
                        )
                    }
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 200, maximum: 320), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(section.items, id: \.objectID) { item in
                            cardButton(for: item)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func cardButton(for item: Item) -> some View {
        let isTicked = multiSelection?.wrappedValue.contains(item.objectID) ?? false
        let isSelected = multiSelection == nil ? item.objectID == selectedID : isTicked
        return Button {
            if let multiSelection {
                if isTicked {
                    multiSelection.wrappedValue.remove(item.objectID)
                } else {
                    multiSelection.wrappedValue.insert(item.objectID)
                }
            } else {
                selectedID = isSelected ? nil : item.objectID
            }
        } label: {
            card(item, isSelected)
                .overlay(alignment: .topLeading) {
                    if multiSelection != nil {
                        Image(systemName: isTicked ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isTicked ? Color.accentColor : .secondary)
                            .background(Circle().fill(.background).padding(2))
                            .padding(8)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func handleDrop(providers: [NSItemProvider]) {
        let logger = self.logger
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, error in
                guard let url else {
                    if let error {
                        logger.warning("Drop failed: \(error.localizedDescription, privacy: .public)")
                    }
                    Task { @MainActor in
                        importErrorMessage = "Couldn't add the PDF you dropped. Try again."
                    }
                    return
                }
                // The provided URL is in a temp location that gets cleaned up when the
                // closure returns; copy to a stable temp path before hopping main actor.
                guard let tempCopy = PDFDropSupport.copyToTempIfNeeded(url, logger: logger) else {
                    Task { @MainActor in
                        importErrorMessage = "Couldn't add the PDF you dropped. Try again."
                    }
                    return
                }
                Task { @MainActor in
                    if let importPDF, let message = PDFDropSupport.importTempCopy(tempCopy, using: importPDF) {
                        importErrorMessage = message
                    }
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
                if let message = importPDF?(url) {
                    importErrorMessage = message
                }
            }
        case .failure(let error):
            logger.warning("File picker failed: \(error.localizedDescription, privacy: .public)")
            importErrorMessage = AppErrorMessages.importMessage(for: error, fileType: "PDF")
        }
    }
}
